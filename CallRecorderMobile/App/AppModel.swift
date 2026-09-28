import AudioCapture
import CallLibrary
import CodexClient
import Foundation
import Observation
import Transcription
import os

/// App-wide state for the iPhone. The same library, transcription and AI steps as the Mac (through the shared
/// `CallLibrary`), without the Mac's per-app capture: recordings come from the Broadcast Upload Extension or are
/// imported.
@Observable
@MainActor
final class AppModel {
    private(set) var recordings: [RecordingItem] = SampleData.recordings
    var selectedID: RecordingItem.ID?
    /// Filters the list; empty shows every recording.
    var searchText = ""
    private(set) var errorMessage: String?
    /// A short confirmation shown after an action that has no other visible result (added to Reminders).
    private(set) var notice: String?
    /// Recordings being transcribed right now, with the current step.
    private(set) var processingStages: [UUID: PipelineStage] = [:]
    private(set) var processingErrors: [UUID: String] = [:]
    /// Recordings whose transcript is being turned into a summary and tasks.
    private(set) var analyzingIDs: Set<UUID> = []
    private(set) var analysisErrors: [UUID: String] = [:]
    /// People whose voices were named once and are recognised in new recordings.
    private(set) var voiceBook: VoiceBook = .empty

    let pipeline = TranscriptionPipeline()
    private var noticeTask: Task<Void, Never>?
    /// One recording is transcribed at a time: the models are large for a phone.
    private var isWorkingThroughQueue = false

    /// The shared App Group container, so broadcast recordings and imports land in the same place; falls back to
    /// the app's own Documents folder if the App Group is ever unavailable.
    static var recordingsDirectory: URL {
        AppGroupStorage.recordingsDirectory
            ?? URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    var selectedRecording: RecordingItem? {
        recordings.first { $0.id == selectedID }
    }

    var visibleRecordings: [RecordingItem] {
        LibrarySearch.filter(recordings, query: searchText)
    }

    /// Replaces the real recordings with what is on disk; the illustrative sample stays as it is. Call on
    /// launch and every time the app returns to the foreground — there is no FSEvents-style watcher on iOS.
    func reload() async {
        let directory = Self.recordingsDirectory
        let (real, book) = await Task.detached {
            (LibraryLoader.load(from: directory), (try? VoiceBookStore.load(from: directory)) ?? .empty)
        }.value
        recordings = real + recordings.filter(\.isSample)
        voiceBook = book
        // A broadcast that just finished, or a fresh import, is transcribed without waiting to be asked.
        Task { await transcribePending() }
    }

    private func transcribePending() async {
        guard !isWorkingThroughQueue else { return }
        isWorkingThroughQueue = true
        defer { isWorkingThroughQueue = false }
        while let next = recordings.first(where: {
            $0.status == .awaitingProcessing && processingErrors[$0.id] == nil && processingStages[$0.id] == nil
        }) {
            await process(next.id)
        }
    }

    /// Copies audio files into the library; the transcription starts by itself.
    func importAudio(_ urls: [URL]) async {
        let directory = Self.recordingsDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Не удалось создать папку записей: \(error.localizedDescription)"
            return
        }
        let results = await Task.detached {
            urls.map { url in
                Result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try AudioImporter.importFile(at: url, into: directory)
                }
            }
        }.value

        let failures = results.compactMap { result -> String? in
            if case .failure(let error) = result { return error.localizedDescription }
            return nil
        }
        let imported = results.compactMap { try? $0.get() }.map(\.standardizedFileURL)
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        guard !imported.isEmpty else { return }

        await reload()
        selectedID = recordings.first { recording in
            recording.directory.map { imported.contains($0.standardizedFileURL) } ?? false
        }?.id
    }

    /// Transcribes a recording on this iPhone, stores `transcript.json` next to its audio and names the voices
    /// the voice book recognises.
    func process(_ recordingID: UUID) async {
        guard processingStages[recordingID] == nil,
              let recording = recordings.first(where: { $0.id == recordingID }),
              let directory = recording.directory,
              let audio = recording.audio
        else { return }

        processingErrors[recordingID] = nil
        processingStages[recordingID] = .loadingModels
        defer { processingStages[recordingID] = nil }
        do {
            let report: @Sendable (PipelineStage) -> Void = { [weak self] stage in
                Task { @MainActor in
                    if self?.processingStages[recordingID] != nil { self?.processingStages[recordingID] = stage }
                }
            }
            let result: TranscriptionResult
            switch audio {
            case .separated(let app, let mic, let offset):
                let input = PipelineInput(appAudio: app, micAudio: mic, micOffsetSeconds: offset)
                result = try await pipeline.transcribe(input: input, progress: report)
            case .single(let file):
                result = try await pipeline.transcribeSingle(audio: file, progress: report)
            }
            try LibraryStore.saveTranscription(result, in: directory, library: Self.recordingsDirectory)
            await reload()
        } catch {
            processingErrors[recordingID] = error.localizedDescription
        }
    }

    func toggleTask(_ taskID: TaskItem.ID, in recordingID: RecordingItem.ID) {
        recordings = recordings.map { $0.id == recordingID ? $0.togglingTask(taskID) : $0 }

        guard let recording = recordings.first(where: { $0.id == recordingID }),
              let directory = recording.directory,
              let analysis = recording.analysis
        else { return }
        do {
            try AnalysisStore.save(analysis.stored, in: directory)
        } catch {
            errorMessage = "Не удалось сохранить отметку: \(error.localizedDescription)"
        }
    }

    /// Sends the transcript to the chosen AI with a meeting template and stores the summary and tasks next to the
    /// recording. Running it again replaces the previous summary.
    func analyze(_ recordingID: UUID, using account: AIAccountModel, template: AnalysisTemplate) async {
        guard !analyzingIDs.contains(recordingID),
              let recording = recordings.first(where: { $0.id == recordingID }),
              let directory = recording.directory
        else { return }

        analysisErrors[recordingID] = nil
        analyzingIDs.insert(recordingID)
        defer { analyzingIDs.remove(recordingID) }
        do {
            let outcome = try await account.analysis(of: recording.transcriptText, template: template)
            let stored = StoredAnalysis(analysis: outcome.analysis, createdAt: Date(), template: template)
            try AnalysisStore.save(stored, in: directory)
            await reload()
        } catch {
            analysisErrors[recordingID] = error.localizedDescription
        }
    }

    /// Gives a voice of a recording a name (an empty name takes it back) and keeps it next to the audio. A named
    /// voice is also remembered, so the same person is named automatically in later recordings.
    func renameSpeaker(_ label: String, to newName: String, in recordingID: RecordingItem.ID) {
        recordings = recordings.map { $0.id == recordingID ? $0.renamingSpeaker(label, to: newName) : $0 }

        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else {
            return
        }
        do {
            try SpeakerNamesStore.save(recording.speakerNames, in: directory)
            if let book = try LibraryStore.rememberVoice(label, as: newName, from: directory, library: Self.recordingsDirectory) {
                voiceBook = book
            }
        } catch {
            errorMessage = "Не удалось сохранить имя: \(error.localizedDescription)"
        }
    }

    /// Corrects the text of one transcript line; the summary is marked as possibly out of date.
    func editLine(_ lineID: TranscriptLine.ID, to text: String, in recordingID: RecordingItem.ID) {
        let now = Date()
        recordings = recordings.map { $0.id == recordingID ? $0.editingLine(lineID, to: text, at: now) : $0 }
        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else {
            return
        }
        do {
            try LibraryStore.saveEdit(lineID: lineID, text: text, in: directory, at: now)
        } catch {
            errorMessage = "Не удалось сохранить исправление: \(error.localizedDescription)"
        }
    }

    func forgetVoice(_ profileID: VoiceProfile.ID) {
        do {
            voiceBook = try LibraryStore.forgetVoice(profileID, library: Self.recordingsDirectory)
        } catch {
            errorMessage = "Не удалось забыть голос: \(error.localizedDescription)"
        }
    }

    func addToReminders(_ tasks: [TaskItem], from recording: RecordingItem) async {
        do {
            let count = try await RemindersExporter().add(tasks, from: recording)
            announce(count == 0 ? "Все задачи уже выполнены" : "Добавлено в Напоминания: \(count)")
        } catch {
            errorMessage = "Не удалось добавить в Напоминания: \(error.localizedDescription)"
        }
    }

    /// Writes the export into a temporary file for the share sheet; `nil` (with the error shown) if it failed.
    func exportFile(of recording: RecordingItem, asPDF: Bool, includesTranscript: Bool) -> URL? {
        let options = RecordingExport.Options(includesTranscript: includesTranscript)
        let name = RecordingExport.fileName(of: recording, extension: asPDF ? "pdf" : "md")
        let file = FileManager.default.temporaryDirectory.appending(path: name)
        do {
            let data = asPDF
                ? try PDFRenderer.pdf(fromHTML: RecordingExport.html(of: recording, options: options))
                : Data(RecordingExport.markdown(of: recording, options: options).utf8)
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            errorMessage = "Не удалось подготовить файл: \(error.localizedDescription)"
            return nil
        }
    }

    /// Deletes a recording's folder from disk and removes it from the list. Permanent — iOS apps have no Trash
    /// of their own to recover from, unlike macOS. Does nothing for the illustrative sample.
    func delete(_ recordingID: UUID) {
        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            recordings.removeAll { $0.id == recordingID }
            if selectedID == recordingID { selectedID = nil }
        } catch {
            errorMessage = "Не удалось удалить запись: \(error.localizedDescription)"
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func announce(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            notice = nil
        }
    }
}

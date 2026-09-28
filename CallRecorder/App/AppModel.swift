import AppKit
import AudioCapture
import CallLibrary
import CodexClient
import Localization
import Observation
import os
import SwiftUI
import Transcription
import UniformTypeIdentifiers

private let appLog = Logger(subsystem: "app.callrecorder.dev", category: "app")

/// App-wide state. It lives in the app process, not in a window, so closing the window neither stops a
/// recording nor loses the library.
@Observable
@MainActor
final class AppModel {
    enum RecorderPhase: Equatable {
        case idle
        case starting
        case recording(since: Date)
        case stopping
    }

    /// The person's own recordings, as found on disk.
    private(set) var realRecordings: [RecordingItem] = []
    /// Kept in memory so a rename or a ticked task on a sample survives while it is shown.
    private var samples = SampleData.recordings
    /// Samples are decided only after the library was read, so they never flash up at launch.
    private var hasLoadedLibrary = false

    var hasLoadedLibraryOnce: Bool { hasLoadedLibrary }
    let preferences: AppPreferences
    var selectedID: RecordingItem.ID? {
        didSet { if selectedID != nil { libraryPage = nil } }
    }
    /// Routes the main window to the recorder screen.
    var showsRecorder = false {
        didSet { if showsRecorder { libraryPage = nil } }
    }
    /// A page about the whole library instead of one recording: every task, or questions to the meetings.
    var libraryPage: LibraryPage? {
        didSet {
            guard libraryPage != nil else { return }
            selectedID = nil
            showsRecorder = false
        }
    }
    /// A moment to show once its recording is open: the player goes there and the transcript scrolls to it.
    var pendingMoment: PendingMoment?
    /// Conversations with the AI about the meetings, for this run of the app.
    var chats: [ChatScope: [ChatTurn]] = [:]
    /// Brings the main window forward, also when it was closed; set by the first view that can open windows.
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
    /// Spotlight's index of the recordings, kept in step on every reload.
    let spotlight = SpotlightIndex()
    /// Phrases recognised during the running call, when that is turned on.
    /// The calendar meeting a recording started now would be linked to, for the recording screen.
    var meetingNow: CalendarEvent?
    var liveLines: [LiveLine] = []
    var liveStats = LiveStats()
    @ObservationIgnored var liveTranscriber: LiveTranscriber?
    @ObservationIgnored var liveAudioSink: AsyncStream<LiveAudio>.Continuation?
    @ObservationIgnored var liveTasks: [Task<Void, Never>] = []
    /// Filters the sidebar; empty shows every recording.
    var searchText = ""
    private(set) var apps: [SourceApp] = []
    var selectedBundleID: String?
    private(set) var phase: RecorderPhase = .idle {
        didSet {
            let wasRecording = if case .recording = oldValue { true } else { false }
            if wasRecording != isRecording { onRecordingChanged?(isRecording) }
        }
    }
    /// Told when a recording starts or stops, so the helpers can hold the mark shortcut only during a call.
    var onRecordingChanged: ((Bool) -> Void)?
    /// Moments marked important in the running recording, in seconds from its start.
    private(set) var currentMarks: [TimeInterval] = []
    /// True for a moment after a mark, so the menu bar icon can confirm it without a sound.
    private(set) var justMarked = false
    private var markFlashTask: Task<Void, Never>?
    private(set) var errorMessage: String? {
        didSet {
            guard let errorMessage else { return }
            appLog.error("shown to the person: \(errorMessage, privacy: .public)")
            let stamped = "\(Date().formatted(date: .omitted, time: .standard)) \(errorMessage)"
            recentProblems = Array((recentProblems + [stamped]).suffix(Self.keptProblems))
        }
    }
    /// The last errors shown, for a problem report.
    private(set) var recentProblems: [String] = []
    private static let keptProblems = 20
    /// A short confirmation shown after an action that has no other visible result (copied, added to Reminders).
    private(set) var notice: String?
    /// Recordings being transcribed right now, with the current step.
    private(set) var processingStages: [UUID: PipelineStage] = [:]
    private(set) var processingErrors: [UUID: String] = [:]
    /// Recordings whose transcript is being turned into a summary and tasks.
    private(set) var analyzingIDs: Set<UUID> = []
    private(set) var analysisErrors: [UUID: String] = [:]
    /// People whose voices were named once and are recognised in new recordings.
    private(set) var voiceBook: VoiceBook = .empty
    /// Shown on the recorder screen while the disk is filling up.
    var diskWarning: String?
    /// Shown while one side of the call has not made a sound since the recording started.
    var soundWarning: String?
    /// Told once per recording when the call app has not been heard at all.
    var onOthersNotHeard: ((_ appName: String) -> Void)?
    /// Recordings whose audio is being compressed right now; they are not transcribed meanwhile.
    var compressingIDs: Set<UUID> = []
    /// Told when a call seems to have ended during a recording, and whether the recording was stopped for it.
    var onCallEnded: ((_ ending: CallEndWatch.Ending, _ appName: String, _ stopped: Bool) -> Void)?
    /// Watches the running recording for the end of the call and for disk space.
    var recordingWatch: Task<Void, Never>?

    enum LibraryPage: Hashable {
        case tasks
        case questions
    }

    struct PendingMoment: Equatable {
        let recordingID: UUID
        let time: TimeInterval
        /// Two requests for the same moment are still two requests.
        let token = UUID()
    }

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    /// Opens a recording, at a given moment when there is one (a task's quote, an answer's source).
    func open(_ recordingID: UUID, at time: TimeInterval? = nil) {
        guard recordings.contains(where: { $0.id == recordingID }) else { return }
        selectedID = recordingID
        showsRecorder = false
        pendingMoment = time.map { PendingMoment(recordingID: recordingID, time: $0) }
    }

    /// Everything the sidebar can list: the person's recordings, plus the samples while the library is empty.
    var recordings: [RecordingItem] {
        realRecordings + SampleData.visible(
            samples, alongside: realRecordings.count, enabled: hasLoadedLibrary && preferences.showsSamples
        )
    }

    let recorder = ScreenCaptureRecorder()
    let calendar = CalendarLookup()
    let pipeline = TranscriptionPipeline()
    private var noticeTask: Task<Void, Never>?

    static var recordingsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "CallRecorder/Recordings", directoryHint: .isDirectory)
    }

    var isRecording: Bool {
        if case .recording = phase { true } else { false }
    }

    var isBusy: Bool {
        phase == .starting || phase == .stopping
    }

    var recordingStart: Date? {
        if case .recording(let since) = phase { since } else { nil }
    }

    /// The pauses of the running recording, on the wall clock, for the timers on screen.
    private(set) var pauseClock = PauseClock()

    var isPaused: Bool { isRecording && pauseClock.isPaused }

    /// Time recorded so far, the pauses left out.
    func recordedTime(at date: Date = .now) -> TimeInterval {
        guard let start = recordingStart else { return 0 }
        return pauseClock.recordedTime(from: start.timeIntervalSince1970, to: date.timeIntervalSince1970)
    }

    /// Pauses the recording or carries on with it. Nothing is written while paused; the recording stays one file.
    func togglePause() async {
        guard isRecording else { return }
        let now = Date().timeIntervalSince1970
        if pauseClock.isPaused {
            await recorder.resume()
            pauseClock.resume(at: now)
        } else {
            await recorder.pause()
            pauseClock.pause(at: now)
        }
    }

    var selectedRecording: RecordingItem? {
        recordings.first { $0.id == selectedID }
    }

    /// What the sidebar lists: everything, or the recordings that match the search.
    var visibleRecordings: [RecordingItem] {
        LibrarySearch.filter(recordings, query: searchText)
    }

    // MARK: Library

    /// Replaces the real recordings with what is on disk; the illustrative samples stay as they are.
    func reload() async {
        let directory = Self.recordingsDirectory
        let (real, book) = await Task.detached {
            (LibraryLoader.load(from: directory), (try? VoiceBookStore.load(from: directory)) ?? .empty)
        }.value
        realRecordings = real
        hasLoadedLibrary = true
        voiceBook = book
        updateSpotlight()
    }

    /// Keeps what depends on the settings in step with them, whoever changes them.
    func followPreferences() {
        withObservationTracking {
            _ = preferences.indexesInSpotlight
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateSpotlight()
                self?.followPreferences()
            }
        }
    }

    /// Indexes the recordings for Spotlight, or empties the index when the person turned that off.
    func updateSpotlight() {
        if preferences.indexesInSpotlight {
            spotlight.update(with: realRecordings)
        } else {
            spotlight.removeAll()
        }
    }

    /// Keeps the list in step with the folder: new captures, imports and files put there by other tools appear
    /// without a restart. Runs until the app quits.
    func watchLibrary() async {
        let directory = Self.recordingsDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            errorMessage = tr("Не удалось создать папку записей: ", "Could not create the recordings folder: ") + error.localizedDescription
            return
        }
        let watcher = DirectoryWatcher(directory: directory)
        watcher.start()
        await prepareLibrary()
        for await _ in watcher.changes {
            // The recorder writes audio continuously; the list is refreshed when the recording is saved.
            guard phase == .idle else { continue }
            await reload()
        }
    }

    /// Asks for audio files and imports them.
    func chooseAudioToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = tr("Выберите аудиозаписи или папку с ними", "Choose audio files or a folder with them")
        panel.prompt = tr("Импортировать", "Import")
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await importAudio(urls) }
    }

    /// Copies audio files (or the audio files of dropped folders) into the library and transcribes them.
    func importAudio(_ urls: [URL]) async {
        let directory = Self.recordingsDirectory
        let results = await Task.detached {
            Self.audioFiles(in: urls).map { url in Result { try AudioImporter.importFile(at: url, into: directory) } }
        }.value

        let failures = results.compactMap { result -> String? in
            if case .failure(let error) = result { return error.localizedDescription }
            return nil
        }
        let imported = results.compactMap { try? $0.get() }.map(\.standardizedFileURL)
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
        guard !imported.isEmpty else { return }

        await reload()
        let ids = recordings.filter { recording in
            recording.directory.map { imported.contains($0.standardizedFileURL) } ?? false
        }.map(\.id)
        selectedID = ids.first
        showsRecorder = false
        Task { for id in ids { await process(id) } }
    }

    /// A folder stands for the audio files inside it; anything else stays as it is.
    private nonisolated static func audioFiles(in urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return [url]
            }
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            return contents
                .filter { RecordingLibrary.audioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
    }

    /// Transcribes a recording on this Mac, stores `transcript.json` next to its audio and names the voices the
    /// voice book recognises.
    func process(_ recordingID: UUID) async {
        guard processingStages[recordingID] == nil, !compressingIDs.contains(recordingID),
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
                    // A late update must not revive a recording whose processing has already finished.
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
            try LibraryStore.applyVocabulary(preferences.vocabulary, in: directory)
            await reload()
        } catch {
            processingErrors[recordingID] = error.localizedDescription
            return
        }
        processingStages[recordingID] = nil
        await compress([recordingID])
    }

    func toggleTask(_ taskID: TaskItem.ID, in recordingID: RecordingItem.ID) {
        update(recordingID) { $0.togglingTask(taskID) }

        guard let recording = recordings.first(where: { $0.id == recordingID }),
              let directory = recording.directory,
              let analysis = recording.analysis
        else { return }
        do {
            try AnalysisStore.save(analysis.stored, in: directory)
        } catch {
            errorMessage = tr("Не удалось сохранить отметку: ", "Could not save the mark: ") + error.localizedDescription
        }
    }

    /// Sends the transcript to the chosen AI with a meeting template and stores the summary and tasks next to the
    /// recording. Running it again replaces the previous summary.
    func analyze(_ recordingID: UUID, using account: CodexAccountModel, template: AnalysisTemplate) async {
        guard !analyzingIDs.contains(recordingID),
              let recording = recordings.first(where: { $0.id == recordingID }),
              let directory = recording.directory
        else { return }

        analysisErrors[recordingID] = nil
        analyzingIDs.insert(recordingID)
        defer { analyzingIDs.remove(recordingID) }
        do {
            // In a series the AI also sees what the last meeting left open, so the summary can say what became of it.
            let followUp = MeetingSeries.previous(of: recording, in: realRecordings).flatMap(MeetingSeries.followUpNote)
            let input = followUp.map { $0 + "\n\n" + recording.analysisText } ?? recording.analysisText
            let outcome = try await account.analysis(of: input, template: template)
            let stored = StoredAnalysis(analysis: outcome.analysis, createdAt: Date(), template: template)
            try AnalysisStore.save(stored, in: directory)
            await reload()
        } catch {
            analysisErrors[recordingID] = error.localizedDescription
            return
        }
        if let summarised = realRecordings.first(where: { $0.id == recordingID }) { writeNote(of: summarised) }
    }

    /// Gives a voice of a recording a name (an empty name takes it back) and keeps it next to the audio. A named
    /// voice is also remembered, so the same person is named automatically in later recordings.
    func renameSpeaker(_ label: String, to newName: String, in recordingID: RecordingItem.ID) {
        update(recordingID) { $0.renamingSpeaker(label, to: newName) }

        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else {
            return // a built-in sample: the change lives in memory only
        }
        do {
            try SpeakerNamesStore.save(recording.speakerNames, in: directory)
            if let book = try LibraryStore.rememberVoice(label, as: newName, from: directory, library: Self.recordingsDirectory) {
                voiceBook = book
            }
        } catch {
            errorMessage = tr("Не удалось сохранить имя: ", "Could not save the name: ") + error.localizedDescription
        }
    }

    /// Corrects the text of one transcript line; the summary is marked as possibly out of date.
    func editLine(_ lineID: TranscriptLine.ID, to text: String, in recordingID: RecordingItem.ID) {
        let now = Date()
        update(recordingID) { $0.editingLine(lineID, to: text, at: now) }
        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else {
            return
        }
        do {
            try LibraryStore.saveEdit(lineID: lineID, text: text, in: directory, at: now)
        } catch {
            errorMessage = tr("Не удалось сохранить исправление: ", "Could not save the correction: ") + error.localizedDescription
        }
    }

    /// Marks a transcript line as important after the call, or takes back the marks pointing at it.
    func toggleMark(on lineID: TranscriptLine.ID, in recordingID: RecordingItem.ID) {
        update(recordingID) { $0.togglingMark(on: lineID) }
        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else {
            return
        }
        do {
            try ImportantMarksStore.save(ImportantMarks(times: recording.marks), in: directory)
        } catch {
            report(error, doing: tr("Не удалось сохранить отметку", "Could not save the mark"))
        }
    }

    /// Labels a recording (a project, a client); a repeat or an empty label changes nothing.
    func addTag(_ tag: String, to recordingID: RecordingItem.ID) {
        guard let recording = realRecordings.first(where: { $0.id == recordingID }) else { return }
        saveTags(TagStore.adding(tag, to: recording.tags), of: recording)
    }

    func removeTag(_ tag: String, from recordingID: RecordingItem.ID) {
        guard let recording = realRecordings.first(where: { $0.id == recordingID }) else { return }
        saveTags(recording.tags.filter { $0 != tag }, of: recording)
    }

    private func saveTags(_ tags: [String], of recording: RecordingItem) {
        guard let directory = recording.directory, tags != recording.tags else { return }
        update(recording.id) { $0.taggedWith(tags) }
        do {
            try TagStore.save(tags, in: directory)
        } catch {
            report(error, doing: tr("Не удалось сохранить теги", "Could not save the tags"))
        }
    }

    func forgetVoice(_ profileID: VoiceProfile.ID) {
        do {
            voiceBook = try LibraryStore.forgetVoice(profileID, library: Self.recordingsDirectory)
        } catch {
            errorMessage = tr("Не удалось забыть голос: ", "Could not forget the voice: ") + error.localizedDescription
        }
    }

    /// Replaces one recording with a changed copy, wherever it lives (the library or the samples).
    private func update(_ recordingID: RecordingItem.ID, _ change: (RecordingItem) -> RecordingItem) {
        if realRecordings.contains(where: { $0.id == recordingID }) {
            realRecordings = realRecordings.map { $0.id == recordingID ? change($0) : $0 }
        } else {
            samples = samples.map { $0.id == recordingID ? change($0) : $0 }
        }
    }

    /// Stops showing the samples; they can be brought back in the settings.
    func hideSamples() {
        if selectedRecording?.isSample == true { selectedID = nil }
        preferences.showsSamples = false
    }

    func revealInFinder(_ recording: RecordingItem) {
        guard let directory = recording.directory else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    /// Moves a recording's folder to the Trash (recoverable there) and removes it from the list. Does nothing
    /// for the illustrative samples, which have no folder on disk.
    func delete(_ recordingID: UUID) {
        guard let recording = recordings.first(where: { $0.id == recordingID }), let directory = recording.directory else { return }
        do {
            try FileManager.default.trashItem(at: directory, resultingItemURL: nil)
            realRecordings.removeAll { $0.id == recordingID }
            if selectedID == recordingID { selectedID = nil }
            updateSpotlight()
        } catch {
            errorMessage = tr("Не удалось удалить запись: ", "Could not delete the recording: ") + error.localizedDescription
        }
    }

    // MARK: Recording

    /// Lists the apps whose sound can be recorded. When the chosen one is gone, a running call app is preferred,
    /// so the shortcut, Siri and the call offer record the call rather than whatever app happens to be first.
    func refreshApps() {
        let running = RunningApplications.list()
        // A meeting in a room is always possible, so it ends the list; it is chosen only on purpose.
        apps = running + [.inPerson]
        if !apps.contains(where: { $0.bundleID == selectedBundleID }) {
            selectedBundleID = running.first { CallDetector.callApps[$0.bundleID] != nil }?.bundleID
                ?? running.first?.bundleID ?? SourceApp.inPersonBundleID
        }
    }

    func startRecording() async {
        guard phase == .idle else { return }
        guard let app = apps.first(where: { $0.bundleID == selectedBundleID }) else {
            errorMessage = tr("Выберите приложение, звук которого нужно записать.", "Choose the app whose sound to record.")
            return
        }
        guard hasRoomToRecord() else { return }
        phase = .starting
        do {
            // In a room every voice comes through the one microphone: the live text signs its lines as the room's.
            let live = startLiveTranscription()
            try await recorder.start(app: app, outputDirectory: Self.recordingsDirectory, live: live)
            currentMarks = []
            pauseClock = PauseClock()
            phase = .recording(since: .now)
            showsRecorder = true
            recordingWatch = watchRecording(of: app)
        } catch {
            stopLiveTranscription()
            phase = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Starts recording a given app, as offered when a call begins.
    func startRecording(bundleID: String) async {
        refreshApps()
        guard apps.contains(where: { $0.bundleID == bundleID }) else {
            errorMessage = tr("Приложение звонка больше не запущено.", "The call app is no longer running.")
            return
        }
        selectedBundleID = bundleID
        await startRecording()
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else if phase == .idle {
            refreshApps()
            await startRecording()
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        phase = .stopping
        recordingWatch?.cancel()
        recordingWatch = nil
        diskWarning = nil
        soundWarning = nil
        stopLiveTranscription()
        do {
            let id = try await recorder.stop()
            phase = .idle
            await reload()
            selectedID = id
            showsRecorder = false
            Task {
                await findMeeting(for: id, announcing: false)
                await process(id)
            }
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            await reload()
        }
    }

    /// Notes the current moment of the running recording as important; the summary gives it extra weight.
    func markImportant() async {
        guard isRecording else { return }
        guard let moment = await recorder.markImportant() else {
            report(tr("Не удалось сохранить отметку.", "Could not save the mark."))
            return
        }
        currentMarks = ImportantMarks(times: currentMarks).adding(moment).times
        justMarked = true
        markFlashTask?.cancel()
        markFlashTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            justMarked = false
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func report(_ error: Error, doing action: String) {
        errorMessage = "\(action): \(error.localizedDescription)"
    }

    /// Shows a problem that is not an `Error`, such as a full disk.
    func report(_ message: String) {
        errorMessage = message
    }

    /// Shows a confirmation for a few seconds.
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

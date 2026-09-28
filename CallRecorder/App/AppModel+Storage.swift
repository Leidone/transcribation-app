import AudioCapture
import CallLibrary
import Foundation
import Localization
import os

private let storageLog = Logger(subsystem: "app.callrecorder.dev", category: "storage")

/// Keeping the library whole and small: recordings cut off by a crash are brought back, and transcribed ones are
/// compressed.
extension AppModel {
    /// The first look at the library in this run.
    func prepareLibrary() async {
        let directory = Self.recordingsDirectory
        // Nothing is being recorded yet, so every folder still marked as recording was cut off.
        let recovered = await Task.detached { RecordingRecovery.recoverInterrupted(in: directory) }.value
        await reload()
        if !recovered.isEmpty {
            announce(recovered.count == 1
                ? tr("Восстановили запись, прерванную сбоем", "Recovered a recording cut off by a crash")
                : tr("Восстановили прерванные сбоем записи: \(recovered.count)", "Recovered recordings cut off by a crash: \(recovered.count)"))
            Task { for id in recovered { await process(id) } }
        }
        await compressBacklog()
    }

    /// Compresses every transcribed recording that still has lossless audio, oldest first, in the background.
    func compressBacklog() async {
        let waiting = realRecordings
            .filter { !$0.transcript.isEmpty && Self.hasLosslessAudio($0) }
            .sorted { $0.startedAt < $1.startedAt }
            .map(\.id)
        guard !waiting.isEmpty else { return }
        let saved = await compress(waiting)
        if saved > 0 { announce(tr("Сжали старые записи: освободилось ", "Compressed older recordings: freed ") + Self.sizeText(saved)) }
    }

    /// Replaces the lossless audio of these recordings with AAC. Returns the bytes freed.
    @discardableResult
    func compress(_ recordingIDs: [UUID]) async -> Int64 {
        guard preferences.compressesAudio else { return 0 }
        var saved: Int64 = 0
        for id in recordingIDs {
            guard processingStages[id] == nil, !compressingIDs.contains(id),
                  let recording = realRecordings.first(where: { $0.id == id }),
                  let folder = recording.directory, Self.hasLosslessAudio(recording)
            else { continue }
            compressingIDs.insert(id)
            let outcome = await Task.detached(priority: .utility) {
                Result { try RecordingCompression.compress(folder: folder) }
            }.value
            compressingIDs.remove(id)
            switch outcome {
            case .success(.compressed(let bytes)):
                saved += bytes
            case .success:
                break
            case .failure(let error):
                // The lossless audio stays as it was, so nothing is lost; the next launch tries again.
                storageLog.error("compression failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if saved > 0 { await reload() }
        return saved
    }

    /// The app's own recordings still in lossless files: calls, and in-person meetings (never imports).
    private static func hasLosslessAudio(_ recording: RecordingItem) -> Bool {
        switch recording.audio {
        case .separated(let app, let mic, _)?:
            return [app, mic].contains { $0.pathExtension.lowercased() == "caf" }
        case .single(let file)?:
            return recording.appBundleID == SourceApp.inPersonBundleID && file.pathExtension.lowercased() == "caf"
        case nil:
            return false
        }
    }

    /// Fixes the person's own words in every transcript already in the library.
    func applyVocabularyToLibrary() async {
        let vocabulary = preferences.vocabulary
        let folders = realRecordings.filter { !$0.transcript.isEmpty }.compactMap(\.directory)
        let changed = await Task.detached(priority: .userInitiated) {
            folders.filter { folder in
                do {
                    return try LibraryStore.applyVocabulary(vocabulary, in: folder)
                } catch {
                    storageLog.error("vocabulary not applied: \(error.localizedDescription, privacy: .public)")
                    return false
                }
            }.count
        }.value
        if changed > 0 { await reload() }
        announce(changed == 0
            ? tr("Исправлять нечего", "Nothing to fix")
            : tr("Исправлено записей: \(changed)", "Recordings fixed: \(changed)"))
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

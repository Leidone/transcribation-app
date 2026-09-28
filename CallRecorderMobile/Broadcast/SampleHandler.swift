import AudioCapture
import ReplayKit
import UserNotifications

enum SampleHandlerError: LocalizedError {
    case noAppGroup

    var errorDescription: String? {
        switch self {
        case .noAppGroup: "Не удалось найти общее хранилище приложения (App Group)."
        }
    }
}

/// Captures a ReplayKit broadcast's system (app) and microphone audio into two lossless CAF files in the shared
/// App Group container, the same file format `ScreenCaptureRecorder` writes on macOS. This extension only
/// records — transcription and Claude analysis happen afterward in the host app, once it is foregrounded (an
/// extension has a tight memory ceiling that model inference would risk exceeding).
///
/// Unlike macOS's `ScreenCaptureRecorder`, there is no chosen app here: ReplayKit's broadcast is the whole
/// screen's system audio mix, started only by the person through the system broadcast picker.
final class SampleHandler: RPBroadcastSampleHandler {
    private var appWriter: AudioFileWriter?
    private var micWriter: AudioFileWriter?
    private var appContinuation: AsyncStream<PCMChunk>.Continuation?
    private var micContinuation: AsyncStream<PCMChunk>.Continuation?
    private var consumers: [Task<Void, Never>] = []
    private var directory: URL?
    private var startedAt: Date?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let root = AppGroupStorage.recordingsDirectory else {
            finishBroadcastWithError(SampleHandlerError.noAppGroup)
            return
        }
        let now = Date()
        let folder = root.appending(path: "\(RecordingTimestamp.folderName(now))-broadcast", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            finishBroadcastWithError(error)
            return
        }
        startedAt = now
        directory = folder

        let appWriter = AudioFileWriter(url: folder.appending(path: "app.caf"))
        let micWriter = AudioFileWriter(url: folder.appending(path: "mic.caf"))
        self.appWriter = appWriter
        self.micWriter = micWriter

        let (appChunks, appContinuation) = AsyncStream<PCMChunk>.makeStream()
        let (micChunks, micContinuation) = AsyncStream<PCMChunk>.makeStream()
        self.appContinuation = appContinuation
        self.micContinuation = micContinuation
        consumers = [
            Task { for await chunk in appChunks { await appWriter.append(chunk) } },
            Task { for await chunk in micChunks { await micWriter.append(chunk) } },
        ]
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        switch sampleBufferType {
        case .audioApp:
            if let chunk = sampleBuffer.makePCMChunk() { appContinuation?.yield(chunk) }
        case .audioMic:
            if let chunk = sampleBuffer.makePCMChunk() { micContinuation?.yield(chunk) }
        default:
            break // video frames are not needed
        }
    }

    /// `RPBroadcastSampleHandler` gives no async hook here, and the extension process is torn down right after
    /// this returns, so the pending writes are awaited synchronously (a semaphore bridging into the async
    /// `AudioFileWriter` actor) rather than lost.
    override func broadcastFinished() {
        appContinuation?.finish()
        micContinuation?.finish()
        guard let directory, let startedAt, let appWriter, let micWriter else { return }
        let consumers = consumers

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            for consumer in consumers { await consumer.value }
            defer { semaphore.signal() }
            guard let appSummary = await appWriter.finish(), let micSummary = await micWriter.finish() else { return }
            let session = RecordingSession(
                id: UUID(),
                startedAt: startedAt,
                app: SourceApp(bundleID: "system.broadcast", name: "Экран"),
                method: .replayKit,
                streams: Streams(
                    app: StreamInfo(
                        file: "app.caf", sampleRate: appSummary.sampleRate, channels: appSummary.channels,
                        firstPTS: appSummary.firstPTS, droppedBuffers: appSummary.droppedBuffers
                    ),
                    mic: StreamInfo(
                        file: "mic.caf", sampleRate: micSummary.sampleRate, channels: micSummary.channels,
                        firstPTS: micSummary.firstPTS, droppedBuffers: micSummary.droppedBuffers
                    )
                )
            )
            try? session.encoded().write(to: directory.appending(path: "session.json"))
            RecordingAvailableSignal.post()
            await Self.announceSaved()
        }
        semaphore.wait()
    }

    /// Tells the person the recording is saved, in case the app is closed; shown only if they allowed notifications.
    private static func announceSaved() async {
        let content = UNMutableNotificationContent()
        content.title = "Запись сохранена"
        content.body = "Откройте Transcribation, чтобы получить расшифровку и итоги."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "broadcast-saved-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

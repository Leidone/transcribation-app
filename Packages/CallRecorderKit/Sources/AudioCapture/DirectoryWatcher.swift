#if os(macOS)
import CoreServices
import Foundation

/// Reports that something changed anywhere below a directory (a new folder, a new or rewritten file), using the
/// system's file-event stream. Events are coalesced: any number of changes gives at least one signal.
/// Call `start` and `stop` from one place.
public final class DirectoryWatcher: @unchecked Sendable {
    public let changes: AsyncStream<Void>

    fileprivate let continuation: AsyncStream<Void>.Continuation
    private let directory: URL
    private let latency: TimeInterval
    private let queue = DispatchQueue(label: "app.callrecorder.directory-watcher", qos: .utility)
    private var stream: FSEventStreamRef?

    public init(directory: URL, latency: TimeInterval = 1.0) {
        self.directory = directory
        self.latency = latency
        (changes, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        stop()
    }

    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().continuation.yield()
        }
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        continuation.finish()
    }
}
#endif

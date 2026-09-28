import Foundation
import Testing
@testable import AudioCapture

struct DirectoryWatcherTests {
    private func firstChange(in watcher: DirectoryWatcher, within seconds: Double) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in watcher.changes { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test("a file appearing in a nested folder is reported")
    func nestedChange() async throws {
        // Arrange
        let root = FileManager.default.temporaryDirectory.appending(path: "watch-\(UUID().uuidString)")
        let nested = root.appending(path: "recording-1")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = DirectoryWatcher(directory: root, latency: 0.2)
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(400))

        // Act
        try Data("transcript".utf8).write(to: nested.appending(path: "transcript.json"))

        // Assert
        #expect(await firstChange(in: watcher, within: 8))
    }

    @Test("nothing is reported while nothing changes")
    func quietDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let watcher = DirectoryWatcher(directory: root, latency: 0.2)
        watcher.start()
        defer { watcher.stop() }
        // Creating the folder just before the start can still be delivered; let that one pass first.
        _ = await firstChange(in: watcher, within: 1.0)

        #expect(await firstChange(in: watcher, within: 1.5) == false)
    }

    @Test("stopping ends the stream")
    func stopEndsStream() async {
        let root = FileManager.default.temporaryDirectory
        let watcher = DirectoryWatcher(directory: root, latency: 0.2)
        watcher.start()

        watcher.stop()

        var ended = true
        for await _ in watcher.changes { ended = false; break }
        #expect(ended)
    }
}

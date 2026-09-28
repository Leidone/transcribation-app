import Foundation

/// Splits a byte stream into newline-terminated lines across arbitrary chunk boundaries.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[pending.startIndex..<newline])
            pending = Data(pending[(newline + 1)...])
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}

/// Thread-safe wrapper for use from `FileHandle` readability handlers.
public final class LockedLineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = LineBuffer()

    public init() {}

    public func append(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.append(chunk)
    }
}

import Foundation

/// Minimal file logger. Writes to `~/Library/Application Support/<bundle>/app.log`
/// so behaviour can be inspected regardless of how the app was launched.
public enum Log {
    private static let lock = NSLock()
    nonisolated(unsafe) private static let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(AIUnderlayKit.bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("app.log")
    }()

    public static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
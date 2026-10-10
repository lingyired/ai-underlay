import Foundation

/// Receives agent hook events over a Unix domain socket. Hooks write one JSON
/// object per line; the receiver parses each line, adapts it, and hands the
/// normalized event to a callback. It is defensive: malformed, oversized, or
/// unknown input is dropped without crashing the listener.
public final class AgentEventReceiver: @unchecked Sendable {
    public typealias Handler = @Sendable (AgentEvent) -> Void

    /// Maximum bytes accepted for a single line (64 KB) — hooks are tiny.
    public static let maxLineBytes = 64 * 1024

    private let socketURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "\(AIUnderlayKit.bundleIdentifier).agent.socket")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    public init(socketURL: URL? = nil, handler: @escaping Handler) {
        self.socketURL = socketURL ?? Self.defaultSocketURL()
        self.handler = handler
    }

    public static func defaultSocketURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent(AIUnderlayKit.bundleIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("agent.sock")
    }

    /// Parses a single line of hook JSON into a normalized event. Pure and
    /// testable; returns nil for anything unrecognized or malformed.
    public static func parse(line: Data) -> AgentEvent? {
        guard line.count <= maxLineBytes,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return nil }
        let provider = (object["provider"] as? String) ?? (object["providerId"] as? String) ?? ""
        guard let adapter = AgentAdapters.adapter(for: provider) else { return nil }
        return adapter.adapt(RawAgentEvent(providerId: provider, payload: object))
    }

    public func start() throws {
        stop()
        // Remove a stale socket file.
        try? FileManager.default.removeItem(at: socketURL)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.ENOTSOCK) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
                path.withCString { src in
                    _ = strncpy(dst, src, 103)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindResult == 0 else { close(listenFD); throw POSIXError(.EADDRINUSE) }

        // Owner-only permissions.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: socketURL.path)

        guard listen(listenFD, 8) == 0 else { close(listenFD); throw POSIXError(.EINVAL) }

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.setCancelHandler { [weak self] in
            guard let self, self.listenFD >= 0 else { return }
            close(self.listenFD)
            self.listenFD = -1
        }
        acceptSource = source
        source.resume()
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        try? FileManager.default.removeItem(at: socketURL)
    }

    private func acceptConnection() {
        let clientFD = accept(listenFD, nil, nil)
        guard clientFD >= 0 else { return }
        defer { close(clientFD) }

        var buffer = Data()
        let readSize = 4096
        var chunk = [UInt8](repeating: 0, count: readSize)
        while true {
            let n = read(clientFD, &chunk, readSize)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > Self.maxLineBytes { break }
        }

        for line in buffer.split(separator: UInt8(ascii: "\n")) {
            if let event = Self.parse(line: Data(line)) {
                handler(event)
            }
        }
    }
}

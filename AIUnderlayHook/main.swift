import Foundation

/// `aiunderlay-hook` — the bridge between an agent's lifecycle hooks and the
/// app's Unix-domain socket.
///
/// An agent invokes this on every hook event (Claude Code via `~/.claude/settings.json`,
/// Codex via `~/.codex/hooks.json`), piping the hook JSON on stdin. We reduce it
/// to whitelisted metadata and write one line to the app's socket, then exit 0
/// immediately.
///
/// Contract, in order of importance:
///   1. Never block or fail the agent. Every error path exits 0; a missing or
///      dead socket is not the agent's problem.
///   2. Never forward conversation content — see `HookEventPayload.reduce`.
///   3. Start fast. This runs inside the agent's tool loop, so no framework
///      linking and no work beyond read → reduce → write.

func failQuietly() -> Never {
    exit(0)
}

// MARK: - Arguments

var provider: String?
var event: String?
var socketPath: String?

var args = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < args.count {
    let arg = args[index]
    switch arg {
    case "--event":
        index += 1
        if index < args.count { event = args[index] }
    case "--socket":
        index += 1
        if index < args.count { socketPath = args[index] }
    case "--provider":
        index += 1
        if index < args.count { provider = args[index] }
    default:
        // Accept `--event=Value` too, and ignore our own `--managed-by=` marker
        // and any argument we do not recognize.
        if let eq = arg.firstIndex(of: "=") {
            let key = String(arg[arg.startIndex..<eq])
            let value = String(arg[arg.index(after: eq)...])
            switch key {
            case "--event": event = value
            case "--socket": socketPath = value
            case "--provider": provider = value
            default: break
            }
        }
    }
    index += 1
}

guard let socketPath, !socketPath.isEmpty else { failQuietly() }

// MARK: - Read stdin

let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty,
      let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
else { failQuietly() }

// MARK: - Diagnostics (opt-in)

// Set AIUNDERLAY_HOOK_DEBUG=1 to append the raw payload's *shape* to a log file.
// Only key names and the event/session identifiers are recorded — never prompt
// text, tool arguments, or any other value — so this stays within the same
// "metadata only" boundary as the forwarded event.
if ProcessInfo.processInfo.environment["AIUNDERLAY_HOOK_DEBUG"] == "1" {
    let keys = object.keys.sorted().joined(separator: ",")
    let eventName = (object["hook_event_name"] as? String) ?? (object["event"] as? String) ?? event ?? "-"
    let sessionId = (object["session_id"] as? String) ?? (object["sessionId"] as? String) ?? "-"
    let type = (object["notification_type"] as? String) ?? "-"
    let tool = (object["tool_name"] as? String) ?? "-"
    let line = "[\(provider ?? "-")] event=\(eventName) type=\(type) tool=\(tool) session=\(sessionId) keys=[\(keys)]\n"
    let debugPath = NSString(string: "~/.aiunderlay-hook-debug.log").expandingTildeInPath
    if let handle = FileHandle(forWritingAtPath: debugPath) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(toFile: debugPath, atomically: true, encoding: .utf8)
    }
}

// MARK: - Reduce

guard let reduced = HookEventPayload.reduce(payload: object, provider: provider, event: event),
      let line = HookEventPayload.line(payload: reduced)
else { failQuietly() }

// MARK: - Send

// A connect failure (app not running, stale socket) is expected and benign.
let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { failQuietly() }
defer { close(fd) }

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
socketPath.withCString { src in
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dst in
            _ = strncpy(dst, src, 103)
        }
    }
}

let connected = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else { failQuietly() }

line.withUnsafeBytes { raw in
    guard let base = raw.baseAddress else { return }
    var written = 0
    while written < raw.count {
        let n = write(fd, base + written, raw.count - written)
        if n <= 0 { break }
        written += n
    }
}
exit(0)
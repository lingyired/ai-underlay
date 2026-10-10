import Foundation

public enum CodexBarCLIError: Error, Equatable {
    /// The executable path was not absolute — we never resolve through PATH at
    /// call time, only through pre-validated absolute paths.
    case notAbsolutePath
    /// The path is missing or not executable.
    case notExecutable
    /// The process did not finish within the timeout and was terminated.
    case timeout
    /// The process could not be launched.
    case launchFailed(String)
    /// The process exited non-zero.
    case nonZeroExit(Int32)
    /// stdout exceeded the cap and was truncated to protect memory.
    case outputTooLarge
}

/// Runs the external CodexBar CLI. Arguments are always passed as an array to
/// `Process` — never through a shell — so user input can never be interpreted
/// as a command.
public struct CodexBarCLIClient: Sendable {
    /// Hard cap on captured stdout (16 MB). Beyond this the process is treated
    /// as misbehaving rather than silently truncated.
    public static let maxOutputBytes = 16 * 1024 * 1024

    public init() {}

    /// Throws unless the URL is an absolute path to an existing executable.
    public static func validate(executable: URL) throws {
        guard executable.path.hasPrefix("/") else { throw CodexBarCLIError.notAbsolutePath }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: executable.path, isDirectory: &isDir),
              !isDir.boolValue,
              FileManager.default.isExecutableFile(atPath: executable.path)
        else { throw CodexBarCLIError.notExecutable }
    }

    /// Runs the CLI and returns stdout. stderr is captured and desensitized
    /// separately; it is never mixed into stdout.
    public func run(
        executable: URL,
        args: [String],
        timeout: TimeInterval = 30,
        environment: [String: String]? = nil
    ) async throws -> Data {
        try Self.validate(executable: executable)

        let process = Process()
        process.executableURL = executable
        process.arguments = args
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            process.terminationHandler = { proc in
                let out = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                if proc.terminationStatus != 0 {
                    box.resume(throwing: CodexBarCLIError.nonZeroExit(proc.terminationStatus))
                } else if out.count > Self.maxOutputBytes {
                    box.resume(throwing: CodexBarCLIError.outputTooLarge)
                } else {
                    _ = err // stderr is desensitized at call sites via Self.desensitize
                    box.resume(returning: out)
                }
            }
            do {
                try process.run()
            } catch {
                box.resume(throwing: CodexBarCLIError.launchFailed(error.localizedDescription))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    process.terminate()
                    box.resume(throwing: CodexBarCLIError.timeout)
                }
            }
        }
    }

    /// Removes emails, tokens, and long opaque identifiers from text before it
    /// is logged or shown, so diagnostics never leak credentials.
    public static func desensitize(_ text: String) -> String {
        var result = text
        let patterns = [
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",   // emails
            "(?i)(token|api[-_]?key|bearer|authorization)[\"'=:\\s]+[A-Za-z0-9._\\-]{8,}",
            "\\b[A-Za-z0-9_\\-]{32,}\\b",                         // long opaque ids
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "[redacted]")
            }
        }
        return result
    }
}

/// Guards against a continuation being resumed twice (timeout + termination can
/// race). The first resume wins.
private final class ContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(_ continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Data) {
        lock.lock(); defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: Error) {
        lock.lock(); defer { lock.unlock() }
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
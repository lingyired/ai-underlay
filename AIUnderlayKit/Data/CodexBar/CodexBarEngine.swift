import Foundation

/// `QuotaEngine` backed by an external CodexBar CLI binary.
public struct CodexBarEngine: QuotaEngine {
    public let id = CodexBarUsageDecoder.engineId
    public let executableURL: URL
    public let version: String?
    private let client: CodexBarCLIClient

    public init(executableURL: URL, version: String?, client: CodexBarCLIClient = CodexBarCLIClient()) {
        self.executableURL = executableURL
        self.version = version
        self.client = client
    }

    public func probe() async -> EngineProbe {
        EngineProbe(isAvailable: true, compatibility: .compatible, version: version, executableURL: executableURL)
    }

    public func fetch(provider: String, account: String?) async throws -> ProviderQuotaSnapshot {
        var args = ["usage", "--provider", provider, "--format", "json", "--no-color"]
        if let account { args.append(contentsOf: ["--account", account]) }
        do {
            let data = try await client.run(executable: executableURL, args: args, timeout: 30)
            do {
                return try CodexBarUsageDecoder.decode(data, provider: provider)
            } catch {
                throw QuotaEngineError.decodeFailed("\(error)")
            }
        } catch let error as CodexBarCLIError {
            throw QuotaEngineError.execution(error)
        }
    }
}

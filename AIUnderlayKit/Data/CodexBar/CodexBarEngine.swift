import Foundation

/// `QuotaEngine` backed by an external CodexBar CLI binary.
public struct CodexBarEngine: QuotaEngine {
    public let id = CodexBarUsageDecoder.engineId
    public let executableURL: URL
    public let version: String?
    /// Explicit proxy URL override, e.g. "http://127.0.0.1:10808".
    public let proxyOverride: String?
    let client: CodexBarCLIClient

    public init(
        executableURL: URL,
        version: String?,
        proxyOverride: String? = nil,
        client: CodexBarCLIClient = CodexBarCLIClient()
    ) {
        self.executableURL = executableURL
        self.version = version
        self.proxyOverride = proxyOverride
        self.client = client
    }

    public func probe() async -> EngineProbe {
        EngineProbe(isAvailable: true, compatibility: .compatible, version: version, executableURL: executableURL)
    }

    public func fetch(provider: String, account: String?) async throws -> ProviderQuotaSnapshot {
        var args = ["usage", "--provider", provider, "--format", "json", "--no-color"]
        if let account { args.append(contentsOf: ["--account", account]) }
        do {
            // A GUI app has no shell proxy variables; pass the system proxy
            // settings (or an explicit override) so the CLI can reach the network.
            let env = ProxyEnvironment.mergedEnvironment(override: proxyOverride)
            let data = try await client.run(executable: executableURL, args: args, timeout: 45, environment: env)
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

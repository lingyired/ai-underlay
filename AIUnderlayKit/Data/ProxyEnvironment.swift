import Foundation
import SystemConfiguration

/// Builds the environment for spawned CLI processes.
///
/// A GUI app launched from Finder/`open` does **not** inherit the shell's
/// `HTTP_PROXY`/`HTTPS_PROXY` variables, so a CLI child that needs a proxy
/// silently fails with a TLS error. We therefore read the macOS system proxy
/// settings (System Settings → Network → Proxies) and pass them through, while
/// letting any variables that are already present win.
public enum ProxyEnvironment {
    /// Pure mapping from a SystemConfiguration proxy dictionary to env vars.
    /// Exposed for testing.
    public static func environment(fromSystemProxy dict: [String: Any]) -> [String: String] {
        var env: [String: String] = [:]

        if let host = dict[kSCPropNetProxiesHTTPProxy as String] as? String,
           let port = dict[kSCPropNetProxiesHTTPPort as String] as? Int,
           !host.isEmpty {
            let url = "http://\(host):\(port)"
            env["HTTP_PROXY"] = url
            env["http_proxy"] = url
        }
        if let host = dict[kSCPropNetProxiesHTTPSProxy as String] as? String,
           let port = dict[kSCPropNetProxiesHTTPSPort as String] as? Int,
           !host.isEmpty {
            let url = "http://\(host):\(port)"
            env["HTTPS_PROXY"] = url
            env["https_proxy"] = url
        }
        if let host = dict[kSCPropNetProxiesSOCKSProxy as String] as? String,
           let port = dict[kSCPropNetProxiesSOCKSPort as String] as? Int,
           !host.isEmpty {
            let url = "socks5://\(host):\(port)"
            env["ALL_PROXY"] = url
            env["all_proxy"] = url
        }
        if let exceptions = dict[kSCPropNetProxiesExceptionsList as String] as? [String],
           !exceptions.isEmpty {
            let list = exceptions.joined(separator: ",")
            env["NO_PROXY"] = list
            env["no_proxy"] = list
        }
        return env
    }

    /// Reads the live system proxy settings.
    public static func systemProxyEnvironment() -> [String: String] {
        guard let dict = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return [:] }
        return environment(fromSystemProxy: dict)
    }

    /// The environment a CLI child should run with: the current process
    /// environment, with system-proxy variables filled in for any that are
    /// missing. An explicit `override` (a user-entered proxy URL) takes highest
    /// precedence for the http/https variables.
    public static func mergedEnvironment(override: String? = nil) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (key, value) in systemProxyEnvironment() where env[key] == nil {
            env[key] = value
        }
        if let override, !override.isEmpty {
            env["HTTP_PROXY"] = override
            env["http_proxy"] = override
            env["HTTPS_PROXY"] = override
            env["https_proxy"] = override
        }
        return env
    }
}
import XCTest
import SystemConfiguration
@testable import AIUnderlayKit

final class ProxyEnvironmentTests: XCTestCase {
    func test_mapsHTTPAndHTTPSProxy() {
        let dict: [String: Any] = [
            kSCPropNetProxiesHTTPProxy as String: "127.0.0.1",
            kSCPropNetProxiesHTTPPort as String: 10808,
            kSCPropNetProxiesHTTPSProxy as String: "127.0.0.1",
            kSCPropNetProxiesHTTPSPort as String: 10808,
        ]
        let env = ProxyEnvironment.environment(fromSystemProxy: dict)
        XCTAssertEqual(env["HTTP_PROXY"], "http://127.0.0.1:10808")
        XCTAssertEqual(env["HTTPS_PROXY"], "http://127.0.0.1:10808")
        XCTAssertEqual(env["http_proxy"], "http://127.0.0.1:10808")
    }

    func test_mapsSOCKSToAllProxy() {
        let dict: [String: Any] = [
            kSCPropNetProxiesSOCKSProxy as String: "127.0.0.1",
            kSCPropNetProxiesSOCKSPort as String: 10808,
        ]
        let env = ProxyEnvironment.environment(fromSystemProxy: dict)
        XCTAssertEqual(env["ALL_PROXY"], "socks5://127.0.0.1:10808")
    }

    func test_mapsExceptionsToNoProxy() {
        let dict: [String: Any] = [
            kSCPropNetProxiesExceptionsList as String: ["localhost", "*.local"],
        ]
        let env = ProxyEnvironment.environment(fromSystemProxy: dict)
        XCTAssertEqual(env["NO_PROXY"], "localhost,*.local")
    }

    func test_emptyDictYieldsNoProxyVars() {
        XCTAssertTrue(ProxyEnvironment.environment(fromSystemProxy: [:]).isEmpty)
    }

    func test_emptyHostIsIgnored() {
        let dict: [String: Any] = [
            kSCPropNetProxiesHTTPProxy as String: "",
            kSCPropNetProxiesHTTPPort as String: 10808,
        ]
        XCTAssertNil(ProxyEnvironment.environment(fromSystemProxy: dict)["HTTP_PROXY"])
    }
}

import XCTest
@testable import AIUnderlayKit

/// The stats-endpoint client. A stub URLProtocol answers instead of the
/// network, so the decode/error paths are tested without reaching lingai.net.
final class DownloadMonitorClientTests: XCTestCase {
    private let url = URL(string: "https://lingai.net/api/dl/statustrio")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func test_validResponse_decodesEveryChannel() async throws {
        stub(status: 200, body: """
        {"project":"statustrio","channels":[
          {"channel":"quark","total":123,"last24h":4,"last7d":20},
          {"channel":"baidu","total":45},
          {"channel":"github","total":678,"last7d":80}
        ]}
        """)

        let snapshot = try await client().fetch(url: url)
        XCTAssertEqual(snapshot.project, "statustrio")
        XCTAssertEqual(snapshot.availability, .valid)
        XCTAssertEqual(snapshot.channels.map(\.channel.rawValue), ["quark", "baidu", "github"])
        XCTAssertEqual(snapshot.stat(for: .quark)?.total, 123)
        XCTAssertEqual(snapshot.stat(for: .quark)?.last24h, 4)
        XCTAssertEqual(snapshot.stat(for: .baidu)?.last24h, nil, "an absent window stays nil")
        XCTAssertEqual(snapshot.stat(for: .github)?.last7d, 80)
        XCTAssertEqual(snapshot.total, 846)
    }

    func test_unknownChannelAndBadCounts_areSkippedNotGuessed() async throws {
        stub(status: 200, body: """
        {"channels":[
          {"channel":"onedrive","total":9},
          {"channel":"quark","total":-3},
          {"channel":"baidu","total":12,"last24h":-1}
        ]}
        """)

        let snapshot = try await client().fetch(url: url)
        XCTAssertEqual(snapshot.channels.map(\.channel.rawValue), ["baidu"])
        XCTAssertEqual(snapshot.stat(for: .baidu)?.last24h, nil, "a negative window is dropped, not clamped")
        // The project falls back to the URL's last path component.
        XCTAssertEqual(snapshot.project, "statustrio")
    }

    func test_emptyChannelList_isAnError_soRetryApplies() async {
        stub(status: 200, body: #"{"project":"statustrio","channels":[]}"#)
        await assertThrows(DownloadMonitorError.emptyChannels) {
            _ = try await self.client().fetch(url: self.url)
        }
    }

    func test_malformedJSON_isADecodeFailure() async {
        stub(status: 200, body: "<html>not json</html>")
        await assertThrows(DownloadMonitorError.decodeFailed) {
            _ = try await self.client().fetch(url: self.url)
        }
    }

    func test_httpErrorStatus_isReported() async {
        stub(status: 503, body: "upstream broken")
        await assertThrows(DownloadMonitorError.httpStatus(503)) {
            _ = try await self.client().fetch(url: self.url)
        }
    }

    func test_transportFailure_isReported() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(DownloadMonitorError.transport) {
            _ = try await self.client().fetch(url: self.url)
        }
    }

    // MARK: - Proxy mapping

    func test_proxyDictionary_mapsSchemes() {
        XCTAssertEqual(
            DownloadMonitorClient.proxyDictionary(from: "http://127.0.0.1:10808")?[kCFProxyTypeKey] as? String,
            kCFProxyTypeHTTP as String
        )
        XCTAssertEqual(
            DownloadMonitorClient.proxyDictionary(from: "https://proxy.example:8443")?[kCFProxyTypeKey] as? String,
            kCFProxyTypeHTTPS as String
        )
        XCTAssertEqual(
            DownloadMonitorClient.proxyDictionary(from: "socks5://127.0.0.1:1080")?[kCFProxyTypeKey] as? String,
            kCFProxyTypeSOCKS as String
        )
        let withPort = DownloadMonitorClient.proxyDictionary(from: "http://127.0.0.1:8080")
        XCTAssertEqual(withPort?[kCFProxyHostNameKey] as? String, "127.0.0.1")
        XCTAssertEqual(withPort?[kCFProxyPortNumberKey] as? Int, 8080)
    }

    func test_proxyDictionary_requiresAnExplicitPort_likeTheSettingsFieldDoes() {
        // The app's proxy field always carries a port (the settings validator
        // rejects portless input), so a portless URL never reaches the client.
        XCTAssertNil(DownloadMonitorClient.proxyDictionary(from: "http://proxy.example"))
        XCTAssertNil(DownloadMonitorClient.proxyDictionary(from: "socks5://proxy.example"))
    }

    func test_proxyDictionary_nilForEmptyOrInvalid_leavingSystemProxyInCharge() {
        XCTAssertNil(DownloadMonitorClient.proxyDictionary(from: nil))
        XCTAssertNil(DownloadMonitorClient.proxyDictionary(from: "   "))
        XCTAssertNil(DownloadMonitorClient.proxyDictionary(from: "proxy.example:8080"))
        XCTAssertNil(DownloadMonitorClient.proxyDictionary(from: "ftp://proxy.example"))
    }

    // MARK: - Helpers

    private func client() -> DownloadMonitorClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return DownloadMonitorClient(session: URLSession(configuration: configuration))
    }

    private func stub(status: Int, body: String) {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
    }

    private func assertThrows(
        _ expected: DownloadMonitorError,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected), but nothing threw", file: file, line: line)
        } catch let error as DownloadMonitorError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }
}

/// Answers every request with a canned response, recording nothing.
private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CancellationError())
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

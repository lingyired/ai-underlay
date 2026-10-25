import XCTest
@testable import AIUnderlayKit

final class DownloadMonitorTests: XCTestCase {
    func test_channelDisplayNames_areUserFacingChinese() {
        XCTAssertEqual(DownloadChannel.quark.displayName, "夸克网盘")
        XCTAssertEqual(DownloadChannel.baidu.displayName, "百度网盘")
        XCTAssertEqual(DownloadChannel.github.displayName, "GitHub 直链")
    }

    func test_snapshot_totalsAcrossChannels_andLooksUpOneChannel() {
        let snapshot = DownloadMonitorSnapshot(
            project: "statustrio",
            channels: [
                DownloadChannelStat(channel: .quark, total: 30, last24h: 2, last7d: 9),
                DownloadChannelStat(channel: .baidu, total: 12),
            ],
            fetchedAt: Date(),
            availability: .valid
        )

        XCTAssertEqual(snapshot.total, 42)
        XCTAssertEqual(snapshot.stat(for: .quark)?.total, 30)
        XCTAssertNil(snapshot.stat(for: .github), "a channel the endpoint never reported is absent, not zero")
    }

    func test_snapshot_codableRoundTrip() throws {
        let snapshot = DownloadMonitorSnapshot(
            project: "statustrio",
            channels: [DownloadChannelStat(channel: .baidu, total: 7, last24h: 1)],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            availability: .valid
        )
        let decoded = try JSONDecoder().decode(
            DownloadMonitorSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(decoded, snapshot)
    }

    func test_countFormat_usesThousandsSeparators() {
        XCTAssertEqual(DownloadCountFormat.text(0), "0")
        XCTAssertEqual(DownloadCountFormat.text(999), "999")
        XCTAssertEqual(DownloadCountFormat.text(1234), "1,234")
        XCTAssertEqual(DownloadCountFormat.text(1234567), "1,234,567")
    }

    func test_windowText_isNilWhenTheEndpointReportsNoWindows() {
        let bare = DownloadChannelStat(channel: .github, total: 5)
        XCTAssertNil(DownloadCountFormat.windowText(bare))

        let windowed = DownloadChannelStat(channel: .quark, total: 5, last24h: 2, last7d: 9)
        XCTAssertEqual(DownloadCountFormat.windowText(windowed), "24 小时 +2 · 7 天 +9")
    }
}

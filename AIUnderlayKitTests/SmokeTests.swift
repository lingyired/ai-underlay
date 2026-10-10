import XCTest
@testable import AIUnderlayKit

final class SmokeTests: XCTestCase {
    func test_kit_exposesVersion() {
        XCTAssertEqual(AIUnderlayKit.version, "0.1.0")
    }

    func test_kit_bundleIdentifierIsStable() {
        XCTAssertEqual(AIUnderlayKit.bundleIdentifier, "com.lingsmbp.aiunderlay")
    }

    func test_hookMarker_containsBundleIdentifier() {
        XCTAssertTrue(AIUnderlayKit.hookMarker.contains(AIUnderlayKit.bundleIdentifier))
    }
}

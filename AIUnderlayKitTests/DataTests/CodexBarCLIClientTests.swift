import XCTest
@testable import AIUnderlayKit

final class CodexBarCLIClientTests: XCTestCase {
    func test_validate_rejectsRelativePath() {
        XCTAssertThrowsError(try CodexBarCLIClient.validate(executable: URL(string: "codexbar")!)) {
            XCTAssertEqual($0 as? CodexBarCLIError, .notAbsolutePath)
        }
    }

    func test_validate_rejectsMissingFile() {
        XCTAssertThrowsError(try CodexBarCLIClient.validate(executable: URL(fileURLWithPath: "/nope/codexbar"))) {
            XCTAssertEqual($0 as? CodexBarCLIError, .notExecutable)
        }
    }

    func test_run_returnsStdout() async throws {
        let client = CodexBarCLIClient()
        let data = try await client.run(executable: URL(fileURLWithPath: "/bin/echo"), args: ["hello"])
        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
    }

    func test_run_timesOut() async throws {
        let client = CodexBarCLIClient()
        do {
            _ = try await client.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                args: ["10"],
                timeout: 0.3
            )
            XCTFail("expected timeout")
        } catch let error as CodexBarCLIError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func test_run_nonZeroExit() async throws {
        let client = CodexBarCLIClient()
        do {
            _ = try await client.run(executable: URL(fileURLWithPath: "/bin/sh"), args: ["-c", "exit 3"])
            XCTFail("expected non-zero exit")
        } catch let error as CodexBarCLIError {
            XCTAssertEqual(error, .nonZeroExit(3))
        }
    }

    func test_desensitize_removesEmail() {
        let out = CodexBarCLIClient.desensitize("accountEmail: user@example.com")
        XCTAssertFalse(out.contains("user@example.com"))
        XCTAssertTrue(out.contains("[redacted]"))
    }

    func test_desensitize_removesToken() {
        let out = CodexBarCLIClient.desensitize("Authorization: Bearer abcdef1234567890xyz")
        XCTAssertFalse(out.contains("abcdef1234567890xyz"))
    }

    func test_desensitize_leavesNormalText() {
        XCTAssertEqual(CodexBarCLIClient.desensitize("CodexBar 0.58.0"), "CodexBar 0.58.0")
    }
}
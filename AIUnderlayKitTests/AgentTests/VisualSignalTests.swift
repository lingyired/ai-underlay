import XCTest
@testable import AIUnderlayKit

/// The attention contract, pure and renderer-free: fixed priority, running as
/// an independent dimension, and never inventing a signal from data that does
/// not exist.
final class VisualSignalTests: XCTestCase {

    // MARK: - Priority is a code constant

    func test_priorityIsErrorWaitingUnreadNone() {
        XCTAssertGreaterThan(AttentionKind.error.priority, AttentionKind.waiting.priority)
        XCTAssertGreaterThan(AttentionKind.waiting.priority, AttentionKind.unread.priority)
        XCTAssertGreaterThan(AttentionKind.unread.priority, AttentionKind.none.priority)
    }

    func test_highestPicksTheTopPriorityKind() {
        XCTAssertEqual(AttentionKind.highest([.unread, .waiting]), .waiting)
        XCTAssertEqual(AttentionKind.highest([.waiting, .error, .unread]), .error)
        XCTAssertEqual(AttentionKind.highest([.none]), .none)
        XCTAssertEqual(AttentionKind.highest([]), .none)
    }

    // MARK: - The combination matrix

    func test_nothingObservedIsNoVisualAtAll() {
        let signal = AgentSignals().visualSignal
        XCTAssertFalse(signal.isRunning)
        XCTAssertEqual(signal.attention, .none)
        XCTAssertTrue(signal.isIdle)
    }

    func test_unknownSessionsNeverProduceErrorOrRunning() {
        let signal = AgentSignals(unknownCount: 3).visualSignal
        XCTAssertFalse(signal.isRunning)
        XCTAssertEqual(signal.attention, .none)
    }

    func test_runningAloneMovesWithNoAttention() {
        let signal = AgentSignals(activeCount: 1).visualSignal
        XCTAssertTrue(signal.isRunning)
        XCTAssertEqual(signal.attention, .none)
    }

    func test_waitingAloneDoesNotMove() {
        let signal = AgentSignals(waitingApprovalCount: 1).visualSignal
        XCTAssertFalse(signal.isRunning)
        XCTAssertEqual(signal.attention, .waiting)
    }

    func test_errorAloneDoesNotMove() {
        let signal = AgentSignals(errorCount: 1).visualSignal
        XCTAssertFalse(signal.isRunning)
        XCTAssertEqual(signal.attention, .error)
    }

    func test_unreadAloneDoesNotMove() {
        let signal = AgentSignals(unreadCount: 2).visualSignal
        XCTAssertFalse(signal.isRunning)
        XCTAssertEqual(signal.attention, .unread)
    }

    func test_runningWithWaitingKeepsMoving() {
        let signal = AgentSignals(activeCount: 1, waitingInputCount: 1).visualSignal
        XCTAssertTrue(signal.isRunning, "another session is still working")
        XCTAssertEqual(signal.attention, .waiting)
    }

    func test_runningWithUnreadKeepsMoving() {
        let signal = AgentSignals(activeCount: 2, unreadCount: 1).visualSignal
        XCTAssertTrue(signal.isRunning)
        XCTAssertEqual(signal.attention, .unread)
    }

    func test_errorOutranksEverythingWhileRunning() {
        let signal = AgentSignals(activeCount: 1, waitingApprovalCount: 1, errorCount: 1, unreadCount: 1).visualSignal
        XCTAssertTrue(signal.isRunning)
        XCTAssertEqual(signal.attention, .error)
    }

    func test_waitingOutranksUnread() {
        let signal = AgentSignals(waitingInputCount: 1, unreadCount: 4).visualSignal
        XCTAssertEqual(signal.attention, .waiting)
    }

    /// Downgrade path: Error clears, Waiting (which is still present) takes
    /// over — the record is never lost to the stronger one disappearing.
    func test_errorClearingFallsBackToWaiting() {
        let withError = AgentSignals(waitingApprovalCount: 1, errorCount: 1).visualSignal
        XCTAssertEqual(withError.attention, .error)
        let withoutError = AgentSignals(waitingApprovalCount: 1).visualSignal
        XCTAssertEqual(withoutError.attention, .waiting)
    }

    // MARK: - Completed is not unread

    func test_transientCompletionIsNotUnread() {
        let signal = AgentSignals(completedCount: 1).visualSignal
        XCTAssertEqual(signal.attention, .none,
                       "completedCount is a transient acknowledgement, never a durable unread receipt")
        XCTAssertFalse(signal.isRunning)
    }

    func test_unreadMustBeExplicitlySupplied() {
        XCTAssertEqual(AgentSignals.counting([]).unreadCount, 0)
        XCTAssertEqual(AgentSignals(completedCount: 5).unreadCount, 0)
        XCTAssertEqual(AgentSignals(unreadCount: 3).unreadCount, 3)
    }

    func test_unreadAloneIsNotAnEmptySignal() {
        XCTAssertFalse(AgentSignals(unreadCount: 1).isEmpty)
    }

    // MARK: - Providers stay independent

    func test_signalsArePerProvider() {
        let codex = AgentSignals(activeCount: 1)
        let claude = AgentSignals(waitingApprovalCount: 1)
        XCTAssertTrue(codex.visualSignal.isRunning)
        XCTAssertEqual(codex.visualSignal.attention, .none)
        XCTAssertFalse(claude.visualSignal.isRunning)
        XCTAssertEqual(claude.visualSignal.attention, .waiting)
    }

    // MARK: - Speed never fakes a value

    func test_observedSpeedIsNilUntilMeasured() {
        XCTAssertNil(AgentSignals(activeCount: 1).visualSignal.observedOutputTPS,
                     "a live signal never carries the demo's simulated speed")
    }
}

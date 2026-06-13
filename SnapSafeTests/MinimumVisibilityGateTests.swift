//
//  MinimumVisibilityGateTests.swift
//  SnapSafeTests
//
//  The saving HUD must never flash: once shown it stays visible for a
//  minimum duration even if the underlying work (encrypt + save) finishes
//  almost instantly. The gate is balanced (show/hide counting) because a new
//  recording can stop while a previous clip is still encrypting — the HUD
//  hides only when the last outstanding save completes.
//

import XCTest

@testable import SnapSafe

/// Test double for the gate's sleep: records requested durations and suspends
/// until the test releases it, so dismissal timing is fully deterministic.
@MainActor
private final class ManualSleeper {
    private(set) var requested: [TimeInterval] = []
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var prereleased = 0

    func sleep(_ duration: TimeInterval) async {
        requested.append(duration)
        if prereleased > 0 {
            prereleased -= 1
            return
        }
        await withCheckedContinuation { pending.append($0) }
    }

    /// Lets the next (or current) sleeper proceed. Safe to call before the
    /// sleep actually starts; the release is banked.
    func release() {
        if pending.isEmpty {
            prereleased += 1
        } else {
            pending.removeFirst().resume()
        }
    }
}

@MainActor
final class MinimumVisibilityGateTests: XCTestCase {

    private var clock: TestClock!
    private var sleeper: ManualSleeper!
    private var gate: MinimumVisibilityGate!

    override func setUp() {
        super.setUp()
        clock = TestClock()
        sleeper = ManualSleeper()
        let sleeper = self.sleeper!
        gate = MinimumVisibilityGate(
            minimumDuration: 1.0,
            clock: clock,
            sleep: { await sleeper.sleep($0) }
        )
    }

    func test_show_makesVisibleImmediately() {
        XCTAssertFalse(gate.isVisible)

        gate.show()

        XCTAssertTrue(gate.isVisible)
    }

    func test_hide_beforeMinimumDuration_staysVisibleForRemainder() async {
        gate.show()
        clock.advance(by: 0.3)

        let dismissal = gate.hide()

        // Still visible: only 0.3s of the 1.0s minimum has elapsed.
        XCTAssertTrue(gate.isVisible)
        XCTAssertNotNil(dismissal)

        sleeper.release()
        await dismissal?.value

        XCTAssertFalse(gate.isVisible)
        XCTAssertEqual(sleeper.requested.count, 1)
        XCTAssertEqual(sleeper.requested[0], 0.7, accuracy: 0.0001)
    }

    func test_hide_afterMinimumDuration_hidesImmediately() {
        gate.show()
        clock.advance(by: 1.5)

        let dismissal = gate.hide()

        XCTAssertFalse(gate.isVisible)
        XCTAssertNil(dismissal)
        XCTAssertTrue(sleeper.requested.isEmpty)
    }

    func test_show_whileHidePending_cancelsDismissal() async {
        gate.show()
        clock.advance(by: 0.3)
        let dismissal = gate.hide()
        XCTAssertNotNil(dismissal)

        // A new save starts while the dismissal is counting down.
        gate.show()

        sleeper.release()
        await dismissal?.value

        // The canceled dismissal must not have hidden the HUD.
        XCTAssertTrue(gate.isVisible)

        // The new save finishing after the minimum hides immediately.
        clock.advance(by: 2.0)
        let secondDismissal = gate.hide()
        XCTAssertNil(secondDismissal)
        XCTAssertFalse(gate.isVisible)
    }

    func test_hide_withoutShow_isNoop() {
        let dismissal = gate.hide()

        XCTAssertNil(dismissal)
        XCTAssertFalse(gate.isVisible)
        XCTAssertTrue(sleeper.requested.isEmpty)
    }

    func test_overlappingSaves_hideOnlyWhenLastOneFinishes() {
        gate.show()
        gate.show()
        clock.advance(by: 2.0)

        // First save finishing must not hide: the second is still active.
        let firstDismissal = gate.hide()
        XCTAssertNil(firstDismissal)
        XCTAssertTrue(gate.isVisible)

        // Second (last) save finishing hides; minimum already satisfied.
        let secondDismissal = gate.hide()
        XCTAssertNil(secondDismissal)
        XCTAssertFalse(gate.isVisible)
    }

    func test_minimumDuration_countsFromFirstShow_whileContinuouslyVisible() async {
        gate.show()
        clock.advance(by: 0.4)

        // Second overlapping save; HUD has been visible continuously.
        gate.show()
        clock.advance(by: 0.4)

        gate.hide()
        // 0.8s total visibility — last hide still owes 0.2s.
        let dismissal = gate.hide()
        XCTAssertTrue(gate.isVisible)
        XCTAssertNotNil(dismissal)

        sleeper.release()
        await dismissal?.value

        XCTAssertFalse(gate.isVisible)
        XCTAssertEqual(sleeper.requested.count, 1)
        XCTAssertEqual(sleeper.requested[0], 0.2, accuracy: 0.0001)
    }
}

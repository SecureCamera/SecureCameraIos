//
//  MinimumVisibilityGate.swift
//  SnapSafe
//
//  Created by Claude on 6/12/26.
//

import Foundation

/// Drives a transient activity indicator (e.g. the video "Saving…" HUD) that,
/// once shown, stays visible for at least a minimum duration — so an
/// operation that finishes near-instantly reads as a deliberate confirmation
/// instead of an unreadable flash.
///
/// Show/hide calls are balanced: each `show()` must be paired with a `hide()`,
/// and the indicator only dismisses when the last outstanding `show()` is
/// hidden (a new recording can stop while a previous clip is still
/// encrypting). The minimum duration is measured from when the indicator
/// became visible, so continuously-visible overlapping work never re-arms it.
@MainActor
final class MinimumVisibilityGate: ObservableObject {

    @Published private(set) var isVisible = false

    private let minimumDuration: TimeInterval
    private let clock: Clock
    private let sleep: @MainActor (TimeInterval) async -> Void

    private var activeCount = 0
    private var shownAtMonotonic: TimeInterval?
    private var pendingDismissal: Task<Void, Never>?

    /// - Parameters:
    ///   - minimumDuration: Minimum time the indicator stays visible once shown.
    ///   - clock: Time source; injectable for tests.
    ///   - sleep: Suspension primitive for deferred dismissal; injectable for tests.
    init(
        minimumDuration: TimeInterval,
        clock: Clock = SystemClock(),
        sleep: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.minimumDuration = minimumDuration
        self.clock = clock
        self.sleep = sleep
    }

    /// Marks a unit of work as started and shows the indicator. Cancels any
    /// dismissal still counting down from a previous `hide()`.
    func show() {
        activeCount += 1
        pendingDismissal?.cancel()
        pendingDismissal = nil
        if !isVisible {
            shownAtMonotonic = clock.monotonicNow
            isVisible = true
        }
    }

    /// Marks a unit of work as finished. When the last outstanding unit
    /// finishes, hides the indicator — immediately if the minimum duration
    /// has already elapsed, otherwise after the remainder.
    ///
    /// - Returns: The deferred-dismissal task when one was scheduled (tests
    ///   await it); `nil` when the call was a no-op or hid immediately.
    @discardableResult
    func hide() -> Task<Void, Never>? {
        guard activeCount > 0 else { return nil }
        activeCount -= 1
        guard activeCount == 0, isVisible else { return nil }

        let elapsed = clock.monotonicNow - (shownAtMonotonic ?? clock.monotonicNow)
        let remaining = minimumDuration - elapsed
        guard remaining > 0 else {
            isVisible = false
            return nil
        }

        let dismissal = Task { [weak self] in
            guard let self else { return }
            await self.sleep(remaining)
            guard !Task.isCancelled else { return }
            self.isVisible = false
            self.pendingDismissal = nil
        }
        pendingDismissal = dismissal
        return dismissal
    }
}

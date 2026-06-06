//
//  AuthorizationRepository.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import Combine
import FactoryKit


/// Manages user authorization state, including PIN verification and session expiration.
///
/// `@MainActor`-isolated so the mutable session/auth state (the authorization flag
/// and the monotonic timestamp baselines) is only ever touched on one actor. This
/// replaces a previous `@unchecked Sendable`, which silenced the data-race
/// diagnostic without actually serializing access. A `nonisolated init` keeps the
/// type constructible from the non-isolated DI factory closures.
@MainActor
public final class AuthorizationRepository {
    // MARK: - Constants
    public static let MAX_FAILED_ATTEMPTS = 10

    // MARK: - Dependencies
    private let appSettings: SettingsDataSource
    private let encryptionScheme: EncryptionScheme
    private let clock: Clock

    // MARK: - Auth state (StateFlow<Boolean> -> Combine)
    @Published private var isAuthorizedValue: Bool = false
    public var isAuthorized: AnyPublisher<Bool, Never> {
        $isAuthorizedValue.eraseToAnyPublisher()
    }

    // MARK: - Timestamps
    // Monotonic baselines for elapsed-time decisions. Using wall-clock here would
    // let an attacker bypass session timeout or PIN backoff by changing the device
    // clock. `nil` means "not set in this process lifetime".
    private var lastAuthMonotonic: TimeInterval?
    private var lastKeepAliveMonotonic: TimeInterval?
    private var lastFailedMonotonic: TimeInterval?

    // MARK: - Init
    public nonisolated init(
        settings: SettingsDataSource,
        encryptionScheme: EncryptionScheme,
        clock: Clock
    ) {
        self.appSettings = settings
        self.encryptionScheme = encryptionScheme
        self.clock = clock
    }

    // MARK: - Security reset
    public func securityFailureReset() async {
        await appSettings.securityFailureReset()
    }

    // MARK: - Failed attempts
    /// Gets the current number of failed PIN attempts
    public func getFailedAttempts() async -> Int {
        await appSettings.getFailedPinAttempts()
    }

    /// Sets the number of failed PIN attempts
    public func setFailedAttempts(_ count: Int) async {
        await appSettings.setFailedPinAttempts(count)
    }

    /// Increments failed attempts, stores the current timestamp, and returns the new count
    public func incrementFailedAttempts() async -> Int {
        let current = await getFailedAttempts()
        let newCount = current + 1
        await setFailedAttempts(newCount)

        let nowMs = Int64(clock.now.timeIntervalSince1970 * 1000.0)
        await appSettings.setLastFailedAttemptTimestamp(nowMs)
        lastFailedMonotonic = clock.monotonicNow

        return newCount
    }

    /// Gets the timestamp (ms since epoch) of the last failed attempt
    public func getLastFailedAttemptTimestamp() async -> Int64 {
        await appSettings.getLastFailedAttemptTimestamp()
    }

    /// Calculates remaining backoff in seconds based on failed attempts and last failed timestamp
    public func calculateRemainingBackoffSeconds() async -> Int {
        let failedAttempts = await getFailedAttempts()
        guard failedAttempts > 1 else { return 0 }

        let lastFailed = await getLastFailedAttemptTimestamp()
        guard lastFailed > 0 else { return 0 }

        let backoffSeconds = Int(pow(2.0, Double(failedAttempts - 1)))

        let elapsedSeconds: Int
        if let baseline = lastFailedMonotonic {
            elapsedSeconds = Int(clock.monotonicNow - baseline)
        } else {
            // Process restarted since the failed attempt was recorded; the
            // monotonic baseline is gone. Fall back to wall clock but clamp
            // negative deltas to 0 so a backward clock change can't shorten
            // the remaining backoff.
            let nowMs = Int64(clock.now.timeIntervalSince1970 * 1000.0)
            let delta = nowMs - lastFailed
            elapsedSeconds = max(0, Int(delta / 1000))
        }
        let remaining = backoffSeconds - elapsedSeconds

        return max(0, remaining)
    }

    /// Resets failed attempts and clears last failed timestamp
    public func resetFailedAttempts() async {
        await setFailedAttempts(0)
        await appSettings.setLastFailedAttemptTimestamp(0)
        lastFailedMonotonic = nil
    }

    // MARK: - Initial key creation
    public func createKey(pin: String, hashedPin: HashedPin) async -> Bool {
        do {
            try await encryptionScheme.createKey(plainPin: pin, hashedPin: hashedPin)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Session lifecycle
    /// Marks the session as authorized and updates the last authentication time.
    /// Also starts session monitoring.
    public func authorizeSession() {
        lastAuthMonotonic = clock.monotonicNow
        isAuthorizedValue = true
    }

    /// Updates the keep-alive timestamp to extend the session validity
    /// without requiring re-authentication.
    public func keepAliveSession() {
        if isAuthorizedValue {
            lastKeepAliveMonotonic = clock.monotonicNow
        }
    }

    /// Checks if the current session is still valid or has expired.
    public func checkSessionValidity() async -> Bool {
        guard isAuthorizedValue else { return false }

        let timeoutMs = await appSettings.getSessionTimeout() // Int64 (ms)

        // Prefer the keep-alive time if present; else the last auth time.
        // Both are monotonic so the wall clock can't influence expiry.
        guard let pivot = lastKeepAliveMonotonic ?? lastAuthMonotonic else {
            return false
        }
        let elapsedMs = (clock.monotonicNow - pivot) * 1000.0
        let sessionValid = elapsedMs < Double(timeoutMs)

        if !sessionValid {
            isAuthorizedValue = false
        }

        return sessionValid
    }

    /// Explicitly revokes the current authorization session.
    public func revokeAuthorization() {
        isAuthorizedValue = false
        lastAuthMonotonic = nil
        lastKeepAliveMonotonic = nil
    }
}

//
//  AuthorizationRepositoryTests.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//

import XCTest
@testable import SnapSafe
import Mockable
import Foundation


// MARK: - Tests

@MainActor
final class AuthorizationRepositoryTests: XCTestCase {

    // Dependencies
    private var settings: SettingsDataSource!
    private var encryption: MockEncryptionScheme!
    private var pinRepo: MockPinRepository!
    private var clock: TestClock!

    // System under test
    private var auth: AuthorizationRepository!
    private var authorizePin: AuthorizePinUseCase!

    override func setUp() async throws {
        try await super.setUp()

        let testUserDefaults: UserDefaults = UserDefaults.inMemoryForTesting()
        
        self.settings = UserDefaultsSettingsDataSource(
            userDefaults: testUserDefaults,
            sanitizeFileNameDefault: Defaults.sanitizeFileName,
            sanitizeMetadataDefault: Defaults.sanitizeMetadata
        )
        await self.settings.setSessionTimeout(1000)
        
        encryption = MockEncryptionScheme()
        pinRepo = MockPinRepository()
        
        clock = TestClock()

        // Common stubs
        let hashed = HashedPin(hash: "hashed_pin", salt: "salt")
        given(pinRepo).getHashedPin().willReturn(hashed)
        given(pinRepo).verifySecurityPin(.any).willReturn(true)
        given(encryption).deriveAndCacheKey(plainPin: .any, hashedPin: .any).willReturn()

        auth = AuthorizationRepository(
            settings: settings,
            encryptionScheme: encryption,
            clock: clock
        )

        authorizePin = AuthorizePinUseCase(
            authRepository: auth,
            pinRepository: pinRepo,
            encryptionScheme: encryption
        )
    }

    // MARK: Session validity

    func test_checkSessionValidity_whenNotAuthorized_returnsFalse() async {

        let result = await auth.checkSessionValidity()
        XCTAssertFalse(result)
        XCTAssertFalse(auth.isAuthorized.firstValue())
    }

    func test_checkSessionValidity_whenSessionValid_returnsTrue() async {
        let pin = "1234"
        
        await settings.setAppPin(cipheredPin: pin)
        _ = await authorizePin.authorizePin(pin)

        let result = await auth.checkSessionValidity()

        XCTAssertTrue(result)
        XCTAssertTrue(auth.isAuthorized.firstValue())
    }

    func test_checkSessionValidity_whenExpired_returnsFalse() async {
        let pin = "1234"
        
        await settings.setAppPin(cipheredPin: pin)
        await settings.setSessionTimeout(1) // 1 ms

        _ = await authorizePin.authorizePin(pin)

        clock.advance(by: 1.0) // advance well past 1 ms

        let result = await auth.checkSessionValidity()
        XCTAssertFalse(result)
        XCTAssertFalse(auth.isAuthorized.firstValue())
    }

    func test_revokeAuthorization_resetsState() async {
        let pin = "1234"
        
        await settings.setAppPin(cipheredPin: pin)
        _ = await authorizePin.authorizePin(pin)
        XCTAssertTrue(auth.isAuthorized.firstValue())

        auth.revokeAuthorization()

        XCTAssertFalse(auth.isAuthorized.firstValue())
    }

    func test_setSessionTimeout_updatesDuration() async {
        let pin = "1234"
        let customTimeoutMs: Int64 = 30_000
        
        await settings.setAppPin(cipheredPin: pin)
        await settings.setSessionTimeout(customTimeoutMs)

        _ = await authorizePin.authorizePin(pin)
        await XCTAssertTrueAsync(await auth.checkSessionValidity())

        clock.advance(by: 0.010) // 10 ms
        await XCTAssertTrueAsync(await auth.checkSessionValidity())
        
        // Verify timeout was actually set
        let storedTimeout = await settings.getSessionTimeout()
        XCTAssertEqual(customTimeoutMs, storedTimeout)
    }

    // MARK: Failed attempts

    func test_getFailedAttempts_returnsValueFromPrefs() async {
        await settings.setFailedPinAttempts(3)
        
        let result = await auth.getFailedAttempts()
        
        XCTAssertEqual(3, result)
    }

    func test_setFailedAttempts_updatesPrefs() async {
        await auth.setFailedAttempts(5)
        
        let storedValue = await settings.getFailedPinAttempts()
        XCTAssertEqual(5, storedValue)
    }

    func test_incrementFailedAttempts_incrementsAndStoresTimestamp() async {
        await settings.setFailedPinAttempts(2)
        await settings.setLastFailedAttemptTimestamp(0)

        let result = await auth.incrementFailedAttempts()

        XCTAssertEqual(3, result)
        let storedCount = await settings.getFailedPinAttempts()
        XCTAssertEqual(3, storedCount)
        let storedTimestamp = await settings.getLastFailedAttemptTimestamp()
        XCTAssertGreaterThan(storedTimestamp, 0)
    }

    func test_resetFailedAttempts_clearsCountAndTimestamp() async {
        await settings.setFailedPinAttempts(5)
        await settings.setLastFailedAttemptTimestamp(1_000)

        await auth.resetFailedAttempts()

        let storedCount = await settings.getFailedPinAttempts()
        let storedTimestamp = await settings.getLastFailedAttemptTimestamp()
        XCTAssertEqual(0, storedCount)
        XCTAssertEqual(0, storedTimestamp)
    }

    func test_getLastFailedAttemptTimestamp_readsFromPrefs() async {
        let ts: Int64 = 1_234_567_890
        await settings.setLastFailedAttemptTimestamp(ts)

        let result = await auth.getLastFailedAttemptTimestamp()
        
        XCTAssertEqual(ts, result)
    }

    // MARK: Backoff

    func test_calculateRemainingBackoffSeconds_whenNoFailedAttempts_returns0() async {
        await settings.setFailedPinAttempts(0)
        
        let result = await auth.calculateRemainingBackoffSeconds()
        
        XCTAssertEqual(0, result)
    }

    func test_calculateRemainingBackoffSeconds_whenNoTimestamp_returns0() async {
        await settings.setFailedPinAttempts(3)
        await settings.setLastFailedAttemptTimestamp(0)
        
        let result = await auth.calculateRemainingBackoffSeconds()
        
        XCTAssertEqual(0, result)
    }

    func test_calculateRemainingBackoffSeconds_calculatesCorrectly() async {
        let failed = 3
        let nowMs = Int64(clock.now.timeIntervalSince1970 * 1000.0)
        let lastFailedMs = nowMs - 3_000 // 3 seconds ago

        await settings.setFailedPinAttempts(failed)
        await settings.setLastFailedAttemptTimestamp(lastFailedMs)

        let remaining = await auth.calculateRemainingBackoffSeconds()
        
        XCTAssertEqual(0, remaining)
    }

    func test_calculateRemainingBackoffSeconds_whenElapsedExceedsBackoff_returns0() async {
        let failed = 2 // backoff = 4s
        let nowMs = Int64(clock.now.timeIntervalSince1970 * 1000.0)
        let lastFailedMs = nowMs - 5_000 // 5s ago

        await settings.setFailedPinAttempts(failed)
        await settings.setLastFailedAttemptTimestamp(lastFailedMs)

        let result = await auth.calculateRemainingBackoffSeconds()
        
        XCTAssertEqual(0, result)
    }

    // MARK: Security reset delegation

    func test_securityFailureReset_delegatesToPreferences() async {
        let pin = "1234"
        await settings.setAppPin(cipheredPin: pin)
        await settings.setFailedPinAttempts(5)
        await settings.setLastFailedAttemptTimestamp(1_000)

        await auth.securityFailureReset()

        // Verify the reset actually happened by checking the state was cleared
        let storedPin = await settings.getCipheredPin()
        let failedAttempts = await settings.getFailedPinAttempts()
        let lastFailedTimestamp = await settings.getLastFailedAttemptTimestamp()
        
        XCTAssertNil(storedPin)
        XCTAssertEqual(0, failedAttempts)
        XCTAssertEqual(0, lastFailedTimestamp)
    }

    // MARK: Keep-alive

    func test_keepAliveSession_extendsValidity() async {
        let pin = "1234"
        let timeout: Int64 = 1_000 // 1s
        
        await settings.setAppPin(cipheredPin: pin)
        await settings.setSessionTimeout(timeout)

        let initial = Date(timeIntervalSince1970: 1)
        clock.fixed = initial

        _ = await authorizePin.authorizePin(pin)
        XCTAssertTrue(auth.isAuthorized.firstValue())

        clock.fixed = initial.addingTimeInterval(TimeInterval(timeout) / 2000.0) // +0.5s

        await XCTAssertTrueAsync(await auth.checkSessionValidity())

        auth.keepAliveSession()

        // Past original 1s window, but still within extended window
        clock.fixed = initial.addingTimeInterval(1.1)
        let result = await auth.checkSessionValidity()

        XCTAssertTrue(result)
        XCTAssertTrue(auth.isAuthorized.firstValue())
    }
}

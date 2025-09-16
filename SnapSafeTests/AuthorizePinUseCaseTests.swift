//
//  AuthorizePinUseCaseTests.swift
//  SnapSafe
//
//  Created by Claude on 9/5/25.
//

import XCTest
@testable import SnapSafe
import Mockable
import Foundation

@MainActor
final class AuthorizePinUseCaseTests: XCTestCase {

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

        auth = AuthorizationRepository(
            settings: settings,
            encryptionScheme: encryption,
            clock: clock
        )

        authorizePin = AuthorizePinUseCase(
            authRepository: auth,
            pinRepository: pinRepo,
        )
    }
    
    // MARK: - Helper Methods
    
    private func setDefaultStubs() {
        let hashed = HashedPin(hash: "hashed_pin", salt: "salt")
        given(pinRepo).getHashedPin().willReturn(hashed)
        given(pinRepo).verifySecurityPin(.any).willReturn(true)
        given(pinRepo).activatePoisonPill().willReturn()
        given(pinRepo).verifyPoisonPillPin(.any).willReturn(true)
        given(pinRepo).hasPoisonPillPin().willReturn(true)
        given(encryption).deriveAndCacheKey(plainPin: .any, hashedPin: .any).willReturn()
    }
    
    // MARK: - PIN Authorization Tests

    func test_authorizePin_shouldUpdateAuthorizationStateWhenPinIsValid() async throws {
        // Given
        setDefaultStubs()
        let pin = "1234"
        await settings.setAppPin(cipheredPin: pin)

        // When
        let result = await authorizePin.authorizePin(pin)

        // Then
        XCTAssertNotNil(result)
        XCTAssertTrue(auth.isAuthorized.firstValue())
    }

    func test_authorizePin_shouldNotUpdateAuthorizationStateWhenPinIsInvalid() async throws {
        // Given
        let correctPin = "1234"
        let incorrectPin = "5678"
        await settings.setAppPin(cipheredPin: correctPin)

        // Setup custom stubs - no defaults needed
        let hashed = HashedPin(hash: "hashed_pin", salt: "salt")
        given(pinRepo).getHashedPin().willReturn(hashed)
        given(pinRepo).verifySecurityPin(.value(incorrectPin)).willReturn(false)

        // When
        let result = await authorizePin.authorizePin(incorrectPin)

        // Then
        XCTAssertNil(result)
        XCTAssertFalse(auth.isAuthorized.firstValue())
        verify(pinRepo).verifySecurityPin(.value(incorrectPin)).called(.once)
    }

    func test_authorizePin_shouldNotUpdateAuthorizationStateWhenPinIsValidButHashedPinIsNull() async throws {
        // Given
        let pin = "1234"
        
        // Setup custom stubs - getHashedPin returns nil
        given(pinRepo).verifySecurityPin(.value(pin)).willReturn(true)
        given(pinRepo).getHashedPin().willReturn(nil)

        // When
        let result = await authorizePin.authorizePin(pin)

        // Then
        XCTAssertNil(result)
        XCTAssertFalse(auth.isAuthorized.firstValue())
        verify(pinRepo).verifySecurityPin(.value(pin)).called(.once)
    }

    // MARK: - Session Validity Tests

    func test_checkSessionValidity_shouldReturnFalseWhenSessionHasExpired() async throws {
        // Given
        let pin = "1234"
        await settings.setAppPin(cipheredPin: pin)

        // Setup custom stubs - getHashedPin returns nil to simulate expired session
        given(pinRepo).verifySecurityPin(.any).willReturn(true)
        given(pinRepo).getHashedPin().willReturn(nil)

        // Set a very small session timeout (1 millisecond)
        await settings.setSessionTimeout(1)

        _ = await authorizePin.authorizePin(pin)

        // Advance time to expire the session
        clock.advance(by: 0.010) // 10ms

        // When
        let result = await auth.checkSessionValidity()

        // Then
        XCTAssertFalse(result)
        XCTAssertFalse(auth.isAuthorized.firstValue())
    }

    func test_revokeAuthorization_shouldResetAuthorizationState() async throws {
        // Given
        setDefaultStubs()
        let pin = "1234"
        await settings.setAppPin(cipheredPin: pin)
        _ = await authorizePin.authorizePin(pin)
        XCTAssertTrue(auth.isAuthorized.firstValue())

        // When
        auth.revokeAuthorization()

        // Then
        XCTAssertFalse(auth.isAuthorized.firstValue())
    }

    func test_setSessionTimeout_shouldUpdateTheTimeoutDuration() async throws {
        // Given
        setDefaultStubs()
        let pin = "1234"
        let customTimeoutMs: Int64 = 30_000 // 30 seconds
        await settings.setAppPin(cipheredPin: pin)
        await settings.setSessionTimeout(customTimeoutMs)

        // When
        _ = await authorizePin.authorizePin(pin)

        // Then
        await XCTAssertTrueAsync(await auth.checkSessionValidity())

        // Fast-forward time but less than the timeout
        clock.advance(by: 0.010) // 10ms
        await XCTAssertTrueAsync(await auth.checkSessionValidity())
    }

    // MARK: - Failed Attempts Tests

    func test_authorizePin_shouldResetFailedAttemptsWhenPinIsValid() async throws {
        // Given
        setDefaultStubs()
        let pin = "1234"
        await settings.setAppPin(cipheredPin: pin)
        await settings.setFailedPinAttempts(3)
        await settings.setLastFailedAttemptTimestamp(1000)

        // When
        let result = await authorizePin.authorizePin(pin)

        // Then
        XCTAssertNotNil(result)
        let failedAttempts = await settings.getFailedPinAttempts()
        let lastFailedTimestamp = await settings.getLastFailedAttemptTimestamp()
        XCTAssertEqual(0, failedAttempts)
        XCTAssertEqual(0, lastFailedTimestamp)
    }

    // MARK: - Keep Alive Tests

    func test_keepAliveSession_shouldExtendSessionValidity() async throws {
        // Given
        setDefaultStubs()
        let pin = "1234"
        await settings.setAppPin(cipheredPin: pin)

        // Set a session timeout
        let sessionTimeoutMs: Int64 = 1_000 // 1 second
        await settings.setSessionTimeout(sessionTimeoutMs)

        // Set initial time in the test clock
        let initialTime = Date(timeIntervalSince1970: 1)
        clock.fixed = initialTime

        // Authorize the session
        _ = await authorizePin.authorizePin(pin)
        XCTAssertTrue(auth.isAuthorized.firstValue())

        // Advance time by half the session timeout
        clock.fixed = initialTime.addingTimeInterval(TimeInterval(sessionTimeoutMs) / 2000.0)

        // Verify session is still valid
        await XCTAssertTrueAsync(await auth.checkSessionValidity())

        // Keep the session alive
        auth.keepAliveSession()

        // Advance time beyond the original session timeout
        // but within the timeout of the keep-alive
        clock.fixed = initialTime.addingTimeInterval(TimeInterval(sessionTimeoutMs + 100) / 1000.0)

        // When
        let result = await auth.checkSessionValidity()

        // Then
        XCTAssertTrue(result)
        XCTAssertTrue(auth.isAuthorized.firstValue())
    }
}

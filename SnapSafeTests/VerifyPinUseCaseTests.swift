//
//  VerifyPinUseCaseTests.swift
//  SnapSafeTests
//
//  Created by Claude on 9/11/25.
//

import XCTest
import FactoryKit
import Mockable
@testable import SnapSafe

private enum TestError: Error, Equatable {
    case transient
}

@MainActor
final class VerifyPinUseCaseTests: XCTestCase {

    func test_verifyPin_returnsRetryableFailure_whenKeyDerivationThrows() async throws {
        let pin = "1234"
        let hashedPin = HashedPin(hash: "h", salt: "s")

        let pinRepo = MockPinRepository()
        given(pinRepo).hasPoisonPillPin().willReturn(false)
        given(pinRepo).verifyPoisonPillPin(.value(pin)).willReturn(false)
        given(pinRepo).getHashedPin().willReturn(hashedPin)
        given(pinRepo).verifySecurityPin(.value(pin)).willReturn(true)

        let settings = MockSettingsDataSource()
        given(settings).setFailedPinAttempts(.value(0)).willReturn()
        given(settings).setLastFailedAttemptTimestamp(.value(0)).willReturn()

        let throwingScheme = MockEncryptionScheme()
        given(throwingScheme)
            .deriveAndCacheKey(plainPin: .value(pin), hashedPin: .value(hashedPin))
            .willThrow(TestError.transient)

        let passthrough = PassThroughEncryptionScheme()
        let authRepo = AuthorizationRepository(
            settings: settings,
            encryptionScheme: passthrough,
            clock: SystemClock()
        )
        let imageRepo = SecureImageRepository(
            thumbnailCache: ThumbnailCache(),
            encryptionScheme: passthrough
        )
        let authorizePinUseCase = AuthorizePinUseCase(
            authRepository: authRepo,
            pinRepository: pinRepo
        )

        let sut = VerifyPinUseCase(
            authRepository: authRepo,
            imageRepository: imageRepo,
            pinRepository: pinRepo,
            encryptionScheme: throwingScheme,
            authorizePinUseCase: authorizePinUseCase
        )

        let result = await sut.verifyPin(pin)

        switch result {
        case .failure(let error):
            XCTAssertEqual(error as? TestError, .transient)
        case .success, .invalidPin:
            XCTFail("Expected .failure(.transient), got \(result)")
        }
    }

    func test_verifyPin_onInvalidPin_incrementsCounterExactlyOnce_andReturnsNewCount() async throws {
        // M1: the failed-attempt counter must have a single writer (the
        // repository, via incrementFailedAttempts). The use case returns the
        // authoritative new count so the view model never writes it a second
        // time from stale local state.
        let pin = "1234"

        let pinRepo = MockPinRepository()
        given(pinRepo).hasPoisonPillPin().willReturn(false)
        given(pinRepo).verifyPoisonPillPin(.value(pin)).willReturn(false)
        given(pinRepo).getHashedPin().willReturn(nil)
        given(pinRepo).verifySecurityPin(.value(pin)).willReturn(false)

        // Real settings-backed repository so the persisted counter is the
        // single source of truth.
        let settings = UserDefaultsSettingsDataSource(userDefaults: .inMemoryForTesting())
        let passthrough = PassThroughEncryptionScheme()
        let authRepo = AuthorizationRepository(
            settings: settings,
            encryptionScheme: passthrough,
            clock: SystemClock()
        )
        let imageRepo = SecureImageRepository(
            thumbnailCache: ThumbnailCache(),
            encryptionScheme: passthrough
        )
        let authorizePinUseCase = AuthorizePinUseCase(
            authRepository: authRepo,
            pinRepository: pinRepo
        )

        let sut = VerifyPinUseCase(
            authRepository: authRepo,
            imageRepository: imageRepo,
            pinRepository: pinRepo,
            encryptionScheme: passthrough,
            authorizePinUseCase: authorizePinUseCase
        )

        let result = await sut.verifyPin(pin)

        // Persisted counter incremented exactly once (0 -> 1).
        let persisted = await settings.getFailedPinAttempts()
        XCTAssertEqual(persisted, 1, "Invalid PIN must increment the counter exactly once")

        // Result carries the authoritative new count, sourced from the single
        // increment — the caller must not derive it from stale local state.
        guard case .invalidPin(let count) = result else {
            return XCTFail("Expected .invalidPin, got \(result)")
        }
        XCTAssertEqual(count, 1, "Result must carry the post-increment count")
    }

    func test_verifyPin_doesNotInvokePoisonPillVerify_whenNoPoisonPillIsSet() async throws {
        // H5: when hasPoisonPillPin() is false, verifyPoisonPillPin must be
        // short-circuited so we don't run a second Argon2 verification per
        // attempt and don't leak a timing oracle about poison-pill presence.
        let pin = "1234"
        let hashedPin = HashedPin(hash: "h", salt: "s")

        let pinRepo = MockPinRepository()
        given(pinRepo).hasPoisonPillPin().willReturn(false)
        given(pinRepo).verifyPoisonPillPin(.value(pin)).willReturn(false)
        given(pinRepo).getHashedPin().willReturn(hashedPin)
        given(pinRepo).verifySecurityPin(.value(pin)).willReturn(true)

        let settings = MockSettingsDataSource()
        given(settings).setFailedPinAttempts(.value(0)).willReturn()
        given(settings).setLastFailedAttemptTimestamp(.value(0)).willReturn()

        let scheme = MockEncryptionScheme()
        given(scheme)
            .deriveAndCacheKey(plainPin: .value(pin), hashedPin: .value(hashedPin))
            .willReturn()

        let passthrough = PassThroughEncryptionScheme()
        let authRepo = AuthorizationRepository(
            settings: settings,
            encryptionScheme: passthrough,
            clock: SystemClock()
        )
        let imageRepo = SecureImageRepository(
            thumbnailCache: ThumbnailCache(),
            encryptionScheme: passthrough
        )
        let authorizePinUseCase = AuthorizePinUseCase(
            authRepository: authRepo,
            pinRepository: pinRepo
        )

        let sut = VerifyPinUseCase(
            authRepository: authRepo,
            imageRepository: imageRepo,
            pinRepository: pinRepo,
            encryptionScheme: scheme,
            authorizePinUseCase: authorizePinUseCase
        )

        _ = await sut.verifyPin(pin)

        verify(pinRepo).hasPoisonPillPin().called(.once)
        verify(pinRepo).verifyPoisonPillPin(.value(pin)).called(.never)
    }

    func testVerifyPinUseCaseCreation() throws {
        // Test that the use case can be created with all dependencies
        // This is a basic smoke test to ensure the class is properly structured

        let authManager = AuthorizationRepository(
            settings: UserDefaultsSettingsDataSource(),
            encryptionScheme: PassThroughEncryptionScheme(),
            clock: SystemClock()
        )

        let imageManager = SecureImageRepository(
            thumbnailCache: ThumbnailCache(),
            encryptionScheme: PassThroughEncryptionScheme()
        )

        let pinRepository = PinRepositoryImpl(
            dataSource: UserDefaultsSettingsDataSource(),
            encryptionScheme: PassThroughEncryptionScheme(),
            deviceInfo: DeviceInfoDataSourceImpl(),
            pinCrypto: PinCryptoImpl()
        )

        let authorizePinUseCase = AuthorizePinUseCase(
            authRepository: authManager,
            pinRepository: pinRepository
        )

        let verifyPinUseCase = VerifyPinUseCase(
            authRepository: authManager,
            imageRepository: imageManager,
            pinRepository: pinRepository,
            encryptionScheme: PassThroughEncryptionScheme(),
            authorizePinUseCase: authorizePinUseCase
        )

        XCTAssertNotNil(verifyPinUseCase)
    }

    func testVerifyPinUseCaseIntegrationWithDI() throws {
        // Test that the use case can be created via dependency injection
        let verifyPinUseCase = Container.shared.verifyPinUseCase()
        XCTAssertNotNil(verifyPinUseCase)
    }
}

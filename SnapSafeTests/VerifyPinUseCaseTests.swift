//
//  VerifyPinUseCaseTests.swift
//  SnapSafeTests
//
//  Created by Claude on 9/11/25.
//

import XCTest
import FactoryKit
@testable import SnapSafe

@MainActor
final class VerifyPinUseCaseTests: XCTestCase {

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

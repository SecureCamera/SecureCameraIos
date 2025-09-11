//
//  VerifyPinUseCaseTests.swift
//  SnapSafeTests
//
//  Created by Claude on 9/11/25.
//

import XCTest
@testable import SnapSafe

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
        
        let encryptionScheme = PassThroughEncryptionScheme()
        
        let authorizePinUseCase = AuthorizePinUseCase(
            authRepository: authManager,
            pinRepository: pinRepository,
            encryptionScheme: encryptionScheme
        )
        
        let verifyPinUseCase = VerifyPinUseCase(
            authManager: authManager,
            imageManager: imageManager,
            pinRepository: pinRepository,
            encryptionScheme: encryptionScheme,
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
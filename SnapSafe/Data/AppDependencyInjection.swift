//
//  AppDependencyInjection.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import FactoryKit
import Logging
import SwiftUI


extension Container {
    
    // MARK: - Logging
    
    /// Factory for encryption logger
    var encryptionLogger: Factory<Logger> {
        self { Logger.encryption }
    }
    
    /// Factory for security logger  
    var securityLogger: Factory<Logger> {
        self { Logger.security }
    }
    
    /// Factory for camera logger
    var cameraLogger: Factory<Logger> {
        self { Logger.camera }
    }
    
    /// Factory for storage logger
    var storageLogger: Factory<Logger> {
        self { Logger.storage }
    }
    
    /// Factory for UI logger
    var uiLogger: Factory<Logger> {
        self { Logger.ui }
    }
    
    /// Factory for app logger
    var appLogger: Factory<Logger> {
        self { Logger.app }
    }
    
    /// Factory for creating subsystem loggers
    func logger(subsystem: String, category: String) -> Logger {
        return Logger.subsystem(subsystem, category: category)
    }
    
    // MARK: - Core Dependencies
    
    var clock: Factory<Clock> {
         self { SystemClock() }
    }
    
    var settingsDataSource: Factory<SettingsDataSource> {
        self { UserDefaultsSettingsDataSource() }.shared
    }
    
    var deviceInfoDataSource: Factory<DeviceInfoDataSource> {
        self { DeviceInfoDataSourceImpl() }
    }
    
    var pinCrypto: Factory<PinCrypto> {
        self { PinCryptoImpl() }.shared
    }
    
    var encryptionScheme: Factory<EncryptionScheme> {
        // Switch between encryption schemes:
        // - PassThroughEncryptionScheme() for testing/development
        // - HardwareEncryptionScheme() for production with hardware backing
        //self { PassThroughEncryptionScheme() }.singleton

        self { HardwareEncryptionScheme(deviceInfo: self.deviceInfoDataSource()) }.singleton
    }
    
    var pinRepository: Factory<PinRepository> {
        self { PinRepositoryImpl(
            dataSource: self.settingsDataSource(),
            encryptionScheme: self.encryptionScheme(),
            deviceInfo: self.deviceInfoDataSource(),
            pinCrypto: self.pinCrypto(),
        ) }.singleton
    }
    
    var authorizationRepository: Factory<AuthorizationRepository> {
        self { AuthorizationRepository(
            settings: self.settingsDataSource(),
            encryptionScheme: self.encryptionScheme(),
            clock: self.clock(),
        ) }.singleton
    }
    
    var authorizedPinUseCase: Factory<AuthorizePinUseCase> {
            self { AuthorizePinUseCase(
                authRepository: self.authorizationRepository(),
                pinRepository: self.pinRepository(),
            )
        }
    }
    
    var createPinUseCase: Factory<CreatePinUseCase> {
        self { CreatePinUseCase(
            authorizationRepository: self.authorizationRepository(),
            encryptionScheme: self.encryptionScheme(),
            pinRepository: self.pinRepository(),
            settingsDataSource: self.settingsDataSource(),
            authorizePinUseCase: self.authorizedPinUseCase(),
        ) }
    }
    
    @MainActor
    var verifyPinUseCase: Factory<VerifyPinUseCase> {
        self { @MainActor in VerifyPinUseCase(
            authManager: self.authorizationRepository(),
            imageManager: self.secureImageRepository(),
            pinRepository: self.pinRepository(),
            encryptionScheme: self.encryptionScheme(),
            authorizePinUseCase: self.authorizedPinUseCase()
        ) }
    }
    
    @MainActor
    var appNavigation: Factory<AppNavigationState> {
        self { @MainActor in AppNavigationState() }.singleton
    }
    
    @MainActor
    var securityOverlayViewModel: Factory<SecurityOverlayViewModel> {
        self { @MainActor in SecurityOverlayViewModel() }.singleton
    }
    
    
    var locationRepository: Factory<LocationRepository> {
        self { LocationRepository() }.singleton
    }
    
    @MainActor
    var thumbnailCache: Factory<ThumbnailCache> {
        self { @MainActor in ThumbnailCache() }.singleton
    }
    
    @MainActor
    var secureImageRepository: Factory<SecureImageRepository> {
        self { @MainActor in SecureImageRepository(
            thumbnailCache: self.thumbnailCache(),
            encryptionScheme: self.encryptionScheme()
        ) }.singleton
    }
    
    @MainActor
    var addDecoyPhotoUseCase: Factory<AddDecoyPhotoUseCase> {
        self { @MainActor in AddDecoyPhotoUseCase(
            pinRepository: self.pinRepository(),
            encryptionScheme: self.encryptionScheme(),
            imageRepository: self.secureImageRepository()
        ) }
    }
    
    @MainActor
    var prepareForSharingUseCase: Factory<PrepareForSharingUseCase> {
        self { @MainActor in PrepareForSharingUseCase() }
    }
    
    @MainActor
    var securityResetUseCase: Factory<SecurityResetUseCase> {
        self { @MainActor in SecurityResetUseCase(
            authManager: self.authorizationRepository(), imageRepository: self.secureImageRepository(), encryptionScheme: self.encryptionScheme(),
        ) }
    }
    
    var createPoisonPillUseCase: Factory<CreatePoisonPillUseCase> {
        self { @MainActor in CreatePoisonPillUseCase(
            pinRepository: self.pinRepository(),
            encryptionScheme: self.encryptionScheme()
        ) }
    }
}

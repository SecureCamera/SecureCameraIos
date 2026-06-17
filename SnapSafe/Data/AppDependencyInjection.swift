//
//  AppDependencyInjection.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import FactoryKit
import SwiftUI


extension Container {

    // MARK: - Core Dependencies
    
    var clock: Factory<Clock> {
         self { SystemClock() }
    }
    
    var settingsDataSource: Factory<SettingsDataSource> {
        self { FileBasedSettingsDataSource() }.shared
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
            authRepository: self.authorizationRepository(),
            imageRepository: self.secureImageRepository(),
            pinRepository: self.pinRepository(),
            encryptionScheme: self.encryptionScheme(),
            authorizePinUseCase: self.authorizedPinUseCase()
        ) }
    }
    
    @MainActor
    var appNavigation: Factory<AppNavigationState> {
        self { @MainActor in AppNavigationState() }.singleton
    }
    
    var locationRepository: Factory<LocationRepository> {
        self { LocationRepository() }.singleton
    }
    
    var thumbnailCache: Factory<ThumbnailCache> {
        self { ThumbnailCache() }.singleton
    }

    var secureImageRepository: Factory<SecureImageRepository> {
        self { SecureImageRepository(
            thumbnailCache: self.thumbnailCache(),
            encryptionScheme: self.encryptionScheme(),
            videoEncryptionService: self.videoEncryptionService()
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
    var addDecoyVideoUseCase: Factory<AddDecoyVideoUseCase> {
        self { @MainActor in AddDecoyVideoUseCase(
            pinRepository: self.pinRepository(),
            encryptionScheme: self.encryptionScheme(),
            imageRepository: self.secureImageRepository()
        ) }
    }
    
    @MainActor
    var removeDecoyPhotoUseCase: Factory<RemoveDecoyPhotoUseCase> {
        self { @MainActor in RemoveDecoyPhotoUseCase(
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
    
    var removePoisonPillUseCase: Factory<RemovePoisonPillUseCase> {
        self { @MainActor in RemovePoisonPillUseCase(
            pinRepository: self.pinRepository(),
            imageRepository: self.secureImageRepository()
        ) }
    }
    
    var pinStrengthCheckUseCase: Factory<PinStrengthCheckUseCase> {
        self { PinStrengthCheckUseCase() }
    }
    
    var invalidateSessionUseCase: Factory<InvalidateSessionUseCase> {
        self { @MainActor in InvalidateSessionUseCase(
            imageRepository: self.secureImageRepository(),
            authManager: self.authorizationRepository(),
        ) }
    }

    // MARK: - Video

    var videoEncryptionService: Factory<VideoEncryptionService> {
        self { VideoEncryptionService() }.shared
    }
}

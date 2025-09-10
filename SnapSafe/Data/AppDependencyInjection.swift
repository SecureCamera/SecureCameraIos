//
//  AppDependencyInjection.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import FactoryKit


extension Container {
    var clock: Factory<Clock> {
         self { SystemClock() }
    }
    
    var settingsDataSource: Factory<SettingsDataSource> {
         self { UserDefaultsSettingsDataSource() }
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
    
}

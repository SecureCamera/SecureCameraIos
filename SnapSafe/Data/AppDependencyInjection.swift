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
        self { PassThroughEncryptionScheme() }.singleton
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
}

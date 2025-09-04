//
//  AppDependencyInjection.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import FactoryKit

extension Container {
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
    
    var PinRepository: Factory<PinRepository> {
        self { PinRepositoryImpl(
            dataSource: self.settingsDataSource(),
            encryptionScheme: self.encryptionScheme(),
            deviceInfo: self.deviceInfoDataSource(),
            pinCrypto: self.pinCrypto(),
        ) }.singleton
    }
    
    var authenticationRepository: Factory<AuthorizationRepository> {
        self { AuthorizationRepository(
            settings: self.settingsDataSource(),
            encryptionScheme: self.encryptionScheme()
        ) }.singleton
    }
}

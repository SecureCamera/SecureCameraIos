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
        self { DeviceInfoDataSource() }
    }
    
    var pinCrypto: Factory<PinCrypto> {
        self { PinCrypto() }.shared
    }
    
    var encryptionScheme: Factory<EncryptionScheme> {
        self { PassThroughEncryptionScheme() }.singleton
    }
    
    var authenticationRepository: Factory<AuthorizationRepository> {
        self { AuthorizationRepository(
            settings: self.settingsDataSource(),
            encryptionScheme: self.encryptionScheme()
        ) }.singleton
    }
}

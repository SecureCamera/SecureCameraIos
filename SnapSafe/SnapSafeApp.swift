//
//  Snap_SafeApp.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/2/25.
//

import SwiftUI
import FactoryKit

@main
struct SnapSafeApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    private let settingsDataSource = Container.shared.settingsDataSource()
    
    var body: some Scene {
        let test = settingsDataSource.sanitizeMetadataDefault
        
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}

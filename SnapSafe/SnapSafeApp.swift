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
    @StateObject private var nav = Container.shared.appNavigation()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
                .environmentObject(nav)
        }
    }
}

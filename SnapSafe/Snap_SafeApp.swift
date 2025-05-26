//
//  Snap_SafeApp.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/2/25.
//

import SwiftUI

@main
struct Snap_SafeApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}

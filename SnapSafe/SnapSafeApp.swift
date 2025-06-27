//
//  SnapSafeApp.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/2/25.
//

import SwiftUI

@main
struct SnapSafeApp: App {
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appearanceMode.colorScheme)
        }
    }
}

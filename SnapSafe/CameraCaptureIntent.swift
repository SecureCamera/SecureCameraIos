//
//  CameraCaptureIntent.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/16/25.
//

import AppIntents
import SwiftUI

@available(iOS 18.0, *)
struct CameraCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Camera"
    // periphery:ignore
    static let description = IntentDescription("Opens SnapSafe camera to capture photos securely")

    // Make this intent available for Action Button and Control Center
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Post a notification to open the camera
        await MainActor.run {
            NotificationCenter.default.post(name: .openCamera, object: nil)
        }

        return .result()
    }
}

// App Shortcuts Provider
@available(iOS 18.0, *)
struct SnapSafeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CameraCaptureIntent(),
            phrases: [
                "Open \(.applicationName) camera",
                "Take a photo with \(.applicationName)",
                "Capture photo in \(.applicationName)"
            ],
            shortTitle: "Open Camera",
            systemImageName: "camera"
        )
    }
}

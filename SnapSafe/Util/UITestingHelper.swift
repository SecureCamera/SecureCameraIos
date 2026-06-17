//
//  UITestingHelper.swift
//  SnapSafe
//
//  Created by Claude on 10/13/25.
//

import Foundation

/// Helper to detect and configure the app for UI testing
enum UITestingHelper {

    /// Check if the app is running in UI testing mode
    static var isUITesting: Bool {
        return CommandLine.arguments.contains("-UITesting")
    }

    /// Check if authentication should be skipped for testing
    static var shouldSkipAuthentication: Bool {
        return CommandLine.arguments.contains("-SkipAuthentication")
    }

    /// Check if onboarding should be reset for testing
    static var shouldResetOnboarding: Bool {
        return CommandLine.arguments.contains("-ResetOnboarding")
    }

    /// Configure the app for UI testing if needed
    static func configureForUITesting() {
        guard isUITesting else { return }

        // You can add any global UI testing configuration here
        // For example:
        // - Disable animations for faster tests
        // - Set up mock data
        // - Configure network stubbing

        print("App running in UI Testing mode")

        if shouldSkipAuthentication {
            print("Skipping authentication for UI tests")
        }

        if shouldResetOnboarding {
            print("Resetting onboarding for UI tests")
        }
    }
}

//
//  PINManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import Combine
import Foundation
import SwiftUI

class PINManager: ObservableObject {
    // Singleton instance
    static let shared = PINManager()

    // Published properties for observers
    @Published var isPINSet: Bool = false
    @Published var requirePINOnResume: Bool = true
    @Published var lastActiveTime: Date = .init()

    // Keys for UserDefaults
    private let pinKey = "snapSafe.userPIN"
    private let pinSetKey = "snapSafe.isPINSet"
    private let requirePINOnResumeKey = "snapSafe.requirePINOnResume"

    // Computed property to check if PIN is set
    private var userDefaults = UserDefaults.standard

    private init() {
        // Load initial values from UserDefaults
        isPINSet = userDefaults.bool(forKey: pinSetKey)
        requirePINOnResume = userDefaults.bool(forKey: requirePINOnResumeKey, defaultValue: true)

        print("PINManager initialized - PIN is set: \(isPINSet), require PIN on resume: \(requirePINOnResume)")

        // Update last active time
        updateLastActiveTime()
    }

    // Set the PIN
    func setPIN(_ pin: String) {
        // Store PIN (not encrypted for now as requested)
        userDefaults.setValue(pin, forKey: pinKey)
        userDefaults.setValue(true, forKey: pinSetKey)
        print("PIN has been set, isPINSet flag set to true")

        // Update published property
        DispatchQueue.main.async {
            self.isPINSet = true
        }
    }

    // Verify the PIN
    func verifyPIN(_ pin: String) -> Bool {
        guard let storedPIN = userDefaults.string(forKey: pinKey) else {
            print("No stored PIN found for verification")
            return false
        }

        // Simple comparison for now
        let isMatch = pin == storedPIN
        print("PIN verification: \(isMatch ? "successful" : "failed")")
        return isMatch
    }

    // Set the requirePINOnResume flag
    func setRequirePINOnResume(_ require: Bool) {
        userDefaults.setValue(require, forKey: requirePINOnResumeKey)
        print("Set requirePINOnResume to: \(require)")

        // Update published property
        DispatchQueue.main.async {
            self.requirePINOnResume = require
        }
    }

    // Update the last active time
    func updateLastActiveTime() {
        lastActiveTime = Date()
    }

    // Clear the PIN (for testing or reset)
    func clearPIN() {
        userDefaults.removeObject(forKey: pinKey)
        userDefaults.setValue(false, forKey: pinSetKey)

        // Update published property
        DispatchQueue.main.async {
            self.isPINSet = false
        }
    }
}

// Extension to simplify getting boolean values with defaults
extension UserDefaults {
    func bool(forKey defaultName: String, defaultValue: Bool = false) -> Bool {
        if object(forKey: defaultName) == nil {
            return defaultValue
        }
        return bool(forKey: defaultName)
    }
}

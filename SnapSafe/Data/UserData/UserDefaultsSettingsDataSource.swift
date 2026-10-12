//
//  UserDefaultsSettingsDataSource.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import Combine

// MARK: - Storage Keys

private enum PrefKeys: String {
    case hasCompletedIntro = "prefs.hasCompletedIntro"           // Bool? (nil when never set)
    case sanitizeFileName   = "prefs.sanitizeFileName"           // Bool
    case sanitizeMetadata   = "prefs.sanitizeMetadata"           // Bool
    case sessionTimeoutMs   = "prefs.sessionTimeoutMs"           // Int64 (stored as Int)
    case cipheredPin        = "prefs.cipheredPin"                // String?
    case failedPinAttempts  = "prefs.failedPinAttempts"          // Int
    case lastFailedAttempt  = "prefs.lastFailedAttempt"          // Int64 (stored as Int)
    case poisonPillPlain    = "prefs.poisonPillPlain"            // String?
    case poisonPillHashed   = "prefs.poisonPillHashed"           // String?
    case alphanumericPin    = "prefs.alphanumericPinEnabled"     // Bool? (nil when never set)
}

// MARK: - Defaults (adjust to taste)

enum Defaults {
    static let sanitizeFileName: Bool = true
    static let sanitizeMetadata: Bool = true
    static let sessionTimeoutMs: Int64 = 300_000
}

// MARK: - UserDefaults Impl

final class UserDefaultsSettingsDataSource: SettingsDataSource, @unchecked Sendable {
    // MARK: - Combine subjects (reflect stored values)
    private nonisolated(unsafe) let hasCompletedIntroSubject: CurrentValueSubject<Bool, Never>
    private nonisolated(unsafe) let sanitizeFileNameSubject: CurrentValueSubject<Bool, Never>
    private nonisolated(unsafe) let sanitizeMetadataSubject: CurrentValueSubject<Bool, Never>
    private nonisolated(unsafe) let sessionTimeoutSubject: CurrentValueSubject<Int64, Never>


    // MARK: - Public publishers
    var hasCompletedIntro: AnyPublisher<Bool, Never> { hasCompletedIntroSubject.eraseToAnyPublisher() }
    var hasCompletedIntroValue: Bool { hasCompletedIntroSubject.value }
    var sanitizeFileName: AnyPublisher<Bool, Never> { sanitizeFileNameSubject.eraseToAnyPublisher() }
    var sanitizeMetadata: AnyPublisher<Bool, Never> { sanitizeMetadataSubject.eraseToAnyPublisher() }
    var sessionTimeout: AnyPublisher<Int64, Never> { sessionTimeoutSubject.eraseToAnyPublisher() }

    // MARK: - Declared defaults (exposed by protocol)
    let sanitizeFileNameDefault: Bool
    let sanitizeMetadataDefault: Bool

    // MARK: - Storage + JSON
    private nonisolated(unsafe) let defaults: UserDefaults

    /// Serializes the failed-attempts read-modify-write. UserDefaults has no atomic
    /// increment, so without this lock concurrent callers could lose an increment.
    private let failedAttemptsLock = NSLock()

    // MARK: - Init
    /// - Parameter userDefaults: UserDefaults instance to use. Defaults to `.standard`.
    /// - Parameter sanitizeFileNameDefault: Default value for sanitize file name setting
    /// - Parameter sanitizeMetadataDefault: Default value for sanitize metadata setting
    init(
        userDefaults: UserDefaults = .standard,
        sanitizeFileNameDefault: Bool = Defaults.sanitizeFileName,
        sanitizeMetadataDefault: Bool = Defaults.sanitizeMetadata
    ) {
        // Use a local store so we don't touch `self` yet
        let store = userDefaults

        self.sanitizeFileNameDefault = sanitizeFileNameDefault
        self.sanitizeMetadataDefault = sanitizeMetadataDefault

        // Seed persisted values if missing (use local `store`)
        if store.object(forKey: PrefKeys.sanitizeFileName.rawValue) == nil {
            store.set(sanitizeFileNameDefault, forKey: PrefKeys.sanitizeFileName.rawValue)
        }
        if store.object(forKey: PrefKeys.sanitizeMetadata.rawValue) == nil {
            store.set(sanitizeMetadataDefault, forKey: PrefKeys.sanitizeMetadata.rawValue)
        }
        if store.object(forKey: PrefKeys.sessionTimeoutMs.rawValue) == nil {
            store.set(Int(Defaults.sessionTimeoutMs), forKey: PrefKeys.sessionTimeoutMs.rawValue)
        }

        // Initialize subjects from stored values (still using local `store`)
        let introStored: Bool = {
            if store.object(forKey: PrefKeys.hasCompletedIntro.rawValue) == nil { return false }
            return store.bool(forKey: PrefKeys.hasCompletedIntro.rawValue)
        }()

        self.hasCompletedIntroSubject = .init(introStored)
        self.sanitizeFileNameSubject = .init(store.bool(forKey: PrefKeys.sanitizeFileName.rawValue))
        self.sanitizeMetadataSubject = .init(store.bool(forKey: PrefKeys.sanitizeMetadata.rawValue))
        self.sessionTimeoutSubject = .init(Int64(store.integer(forKey: PrefKeys.sessionTimeoutMs.rawValue)))

        // Only now assign the property that references `self`
        self.defaults = store
    }

    // MARK: - Keys & PIN
    func getCipheredPin() async -> String? {
        defaults.string(forKey: PrefKeys.cipheredPin.rawValue)
    }

    func setIntroCompleted(_ completed: Bool) async {
        defaults.set(completed, forKey: PrefKeys.hasCompletedIntro.rawValue)
        hasCompletedIntroSubject.send(completed)
    }

    /// Accepts the ciphered PIN and a JSON string for `SchemeConfig`.
    /// If JSON parsing fails, we still set the PIN but leave the previous scheme config untouched.
    func setAppPin(cipheredPin: String) async {
        defaults.set(cipheredPin, forKey: PrefKeys.cipheredPin.rawValue)
    }

    // MARK: - Alphanumeric PIN preference
    func getAlphanumericPinEnabled() async -> Bool {
        if defaults.object(forKey: PrefKeys.alphanumericPin.rawValue) == nil { return false }
        return defaults.bool(forKey: PrefKeys.alphanumericPin.rawValue)
    }

    func setAlphanumericPinEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: PrefKeys.alphanumericPin.rawValue)
    }

    // MARK: - Sanitize prefs
    func setSanitizeFileName(_ sanitize: Bool) async {
        defaults.set(sanitize, forKey: PrefKeys.sanitizeFileName.rawValue)
        sanitizeFileNameSubject.send(sanitize)
    }

    func setSanitizeMetadata(_ sanitize: Bool) async {
        defaults.set(sanitize, forKey: PrefKeys.sanitizeMetadata.rawValue)
        sanitizeMetadataSubject.send(sanitize)
    }

    // MARK: - Failed PIN attempts
    func getFailedPinAttempts() async -> Int {
        let v = defaults.object(forKey: PrefKeys.failedPinAttempts.rawValue)
        return (v as? Int) ?? 0
    }

    func setFailedPinAttempts(_ count: Int) async {
        defaults.set(count, forKey: PrefKeys.failedPinAttempts.rawValue)
    }

    func incrementFailedPinAttempts() async -> Int {
        // Guard the read-modify-write so concurrent callers can't read the same
        // starting value and lose an increment. `withLock` keeps the critical section
        // synchronous (no suspension while holding the lock).
        failedAttemptsLock.withLock {
            let current = (defaults.object(forKey: PrefKeys.failedPinAttempts.rawValue) as? Int) ?? 0
            let newCount = current + 1
            defaults.set(newCount, forKey: PrefKeys.failedPinAttempts.rawValue)
            return newCount
        }
    }

    func getLastFailedAttemptTimestamp() async -> Int64 {
        Int64(defaults.integer(forKey: PrefKeys.lastFailedAttempt.rawValue))
    }

    func setLastFailedAttemptTimestamp(_ timestamp: Int64) async {
        defaults.set(Int(timestamp), forKey: PrefKeys.lastFailedAttempt.rawValue)
    }

    // MARK: - Security reset
    func securityFailureReset() async {
        // Remove sensitive and preference keys
        [
            PrefKeys.cipheredPin,
            PrefKeys.poisonPillPlain,
            PrefKeys.poisonPillHashed,
            PrefKeys.failedPinAttempts,
            PrefKeys.lastFailedAttempt,
            PrefKeys.hasCompletedIntro,
            PrefKeys.sanitizeFileName,
            PrefKeys.sanitizeMetadata,
            PrefKeys.alphanumericPin
        ].forEach { defaults.removeObject(forKey: $0.rawValue) }

        // Restore defaults for observed prefs
        defaults.set(Defaults.sanitizeFileName, forKey: PrefKeys.sanitizeFileName.rawValue)
        defaults.set(Defaults.sanitizeMetadata, forKey: PrefKeys.sanitizeMetadata.rawValue)

        // Emit changes
        hasCompletedIntroSubject.send(false)
        sanitizeFileNameSubject.send(Defaults.sanitizeFileName)
        sanitizeMetadataSubject.send(Defaults.sanitizeMetadata)
        // Leave sessionTimeout as-is (not a security concern)
    }

    // MARK: - Session timeout (direct access)
    func getSessionTimeout() async -> Int64 {
        Int64(defaults.integer(forKey: PrefKeys.sessionTimeoutMs.rawValue))
    }

    func setSessionTimeout(_ timeoutMs: Int64) async {
        defaults.set(Int(timeoutMs), forKey: PrefKeys.sessionTimeoutMs.rawValue)
        sessionTimeoutSubject.send(timeoutMs)
    }
    
    // MARK: - Poison Pill
    func setPoisonPillPin(cipheredHashedPin: String, cipheredPlainPin: String) async {
        defaults.set(cipheredHashedPin, forKey: PrefKeys.poisonPillHashed.rawValue)
        defaults.set(cipheredPlainPin, forKey: PrefKeys.poisonPillPlain.rawValue)
    }

    func getPlainPoisonPillPin() async -> String? {
        defaults.string(forKey: PrefKeys.poisonPillPlain.rawValue)
    }

    func getHashedPoisonPillPin() async -> String? {
        defaults.string(forKey: PrefKeys.poisonPillHashed.rawValue)
    }

    func activatePoisonPill(ciphered: String) async {
        // Replace the main PIN with the poison-pill ciphered value
        defaults.set(ciphered, forKey: PrefKeys.cipheredPin.rawValue)
    }

    func removePoisonPillPin() async {
        defaults.removeObject(forKey: PrefKeys.poisonPillPlain.rawValue)
        defaults.removeObject(forKey: PrefKeys.poisonPillHashed.rawValue)
    }

    func isPinCiphered() async -> Bool {
        defaults.string(forKey: PrefKeys.cipheredPin.rawValue) != nil
    }
}

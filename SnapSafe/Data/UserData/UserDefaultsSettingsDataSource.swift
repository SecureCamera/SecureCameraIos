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
    case cipherKey          = "prefs.cipherKey"                  // String
    case cipheredPin        = "prefs.cipheredPin"                // String?
    case failedPinAttempts  = "prefs.failedPinAttempts"          // Int
    case lastFailedAttempt  = "prefs.lastFailedAttempt"          // Int64 (stored as Int)
    case poisonPillPlain    = "prefs.poisonPillPlain"            // String?
    case poisonPillHashed   = "prefs.poisonPillHashed"           // String?
}

// MARK: - Defaults (adjust to taste)

public enum Defaults {
    public static let sanitizeFileName: Bool = true
    public static let sanitizeMetadata: Bool = true
    public static let sessionTimeoutMs: Int64 = 60_000
    public static let cipherKey: String = "stub-cipher-key" // In production, move to Keychain
}

// MARK: - UserDefaults Impl

public final class UserDefaultsSettingsDataSource: SettingsDataSource {
    // MARK: - Combine subjects (reflect stored values)
    private let hasCompletedIntroSubject: CurrentValueSubject<Bool, Never>
    private let sanitizeFileNameSubject: CurrentValueSubject<Bool, Never>
    private let sanitizeMetadataSubject: CurrentValueSubject<Bool, Never>
    private let sessionTimeoutSubject: CurrentValueSubject<Int64, Never>


    // MARK: - Public publishers
    public var hasCompletedIntro: AnyPublisher<Bool, Never> { hasCompletedIntroSubject.eraseToAnyPublisher() }
    public var sanitizeFileName: AnyPublisher<Bool, Never> { sanitizeFileNameSubject.eraseToAnyPublisher() }
    public var sanitizeMetadata: AnyPublisher<Bool, Never> { sanitizeMetadataSubject.eraseToAnyPublisher() }
    public var sessionTimeout: AnyPublisher<Int64, Never> { sessionTimeoutSubject.eraseToAnyPublisher() }

    // MARK: - Declared defaults (exposed by protocol)
    public let sanitizeFileNameDefault: Bool
    public let sanitizeMetadataDefault: Bool

    // MARK: - Storage + JSON
    private let defaults: UserDefaults
    private let jsonDecoder = JSONDecoder()
    private let jsonEncoder = JSONEncoder()

    // MARK: - Init
    /// - Parameter userDefaults: UserDefaults instance to use. Defaults to `.standard`.
    /// - Parameter sanitizeFileNameDefault: Default value for sanitize file name setting
    /// - Parameter sanitizeMetadataDefault: Default value for sanitize metadata setting
    public init(
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
        if store.string(forKey: PrefKeys.cipherKey.rawValue) == nil {
            store.set(Defaults.cipherKey, forKey: PrefKeys.cipherKey.rawValue)
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
    public func getCipherKey() async -> String {
        defaults.string(forKey: PrefKeys.cipherKey.rawValue) ?? Defaults.cipherKey
    }

    public func getCipheredPin() async -> String? {
        defaults.string(forKey: PrefKeys.cipheredPin.rawValue)
    }

    public func setIntroCompleted(_ completed: Bool) async {
        defaults.set(completed, forKey: PrefKeys.hasCompletedIntro.rawValue)
        hasCompletedIntroSubject.send(completed)
    }

    /// Accepts the ciphered PIN and a JSON string for `SchemeConfig`.
    /// If JSON parsing fails, we still set the PIN but leave the previous scheme config untouched.
    public func setAppPin(cipheredPin: String) async {
        defaults.set(cipheredPin, forKey: PrefKeys.cipheredPin.rawValue)
    }

    // MARK: - Sanitize prefs
    public func setSanitizeFileName(_ sanitize: Bool) async {
        defaults.set(sanitize, forKey: PrefKeys.sanitizeFileName.rawValue)
        sanitizeFileNameSubject.send(sanitize)
    }

    public func setSanitizeMetadata(_ sanitize: Bool) async {
        defaults.set(sanitize, forKey: PrefKeys.sanitizeMetadata.rawValue)
        sanitizeMetadataSubject.send(sanitize)
    }

    // MARK: - Failed PIN attempts
    public func getFailedPinAttempts() async -> Int {
        let v = defaults.object(forKey: PrefKeys.failedPinAttempts.rawValue)
        return (v as? Int) ?? 0
    }

    public func setFailedPinAttempts(_ count: Int) async {
        defaults.set(count, forKey: PrefKeys.failedPinAttempts.rawValue)
    }

    public func getLastFailedAttemptTimestamp() async -> Int64 {
        Int64(defaults.integer(forKey: PrefKeys.lastFailedAttempt.rawValue))
    }

    public func setLastFailedAttemptTimestamp(_ timestamp: Int64) async {
        defaults.set(Int(timestamp), forKey: PrefKeys.lastFailedAttempt.rawValue)
    }

    // MARK: - Security reset
    public func securityFailureReset() async {
        // Remove sensitive and preference keys
        [
            PrefKeys.cipheredPin,
            PrefKeys.poisonPillPlain,
            PrefKeys.poisonPillHashed,
            PrefKeys.failedPinAttempts,
            PrefKeys.lastFailedAttempt,
            PrefKeys.hasCompletedIntro,
            PrefKeys.sanitizeFileName,
            PrefKeys.sanitizeMetadata
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
    public func getSessionTimeout() async -> Int64 {
        Int64(defaults.integer(forKey: PrefKeys.sessionTimeoutMs.rawValue))
    }

    public func setSessionTimeout(_ timeoutMs: Int64) async {
        defaults.set(Int(timeoutMs), forKey: PrefKeys.sessionTimeoutMs.rawValue)
        sessionTimeoutSubject.send(timeoutMs)
    }
    
    // MARK: - Poison Pill
    public func setPoisonPillPin(cipheredHashedPin: String, cipheredPlainPin: String) async {
        defaults.set(cipheredHashedPin, forKey: PrefKeys.poisonPillHashed.rawValue)
        defaults.set(cipheredPlainPin, forKey: PrefKeys.poisonPillPlain.rawValue)
    }

    public func getPlainPoisonPillPin() async -> String? {
        defaults.string(forKey: PrefKeys.poisonPillPlain.rawValue)
    }

    public func getHashedPoisonPillPin() async -> String? {
        defaults.string(forKey: PrefKeys.poisonPillHashed.rawValue)
    }

    public func activatePoisonPill(ciphered: String) async {
        // Replace the main PIN with the poison-pill ciphered value
        defaults.set(ciphered, forKey: PrefKeys.cipheredPin.rawValue)
    }

    public func removePoisonPillPin() async {
        defaults.removeObject(forKey: PrefKeys.poisonPillPlain.rawValue)
        defaults.removeObject(forKey: PrefKeys.poisonPillHashed.rawValue)
    }

    public func isPinCiphered() async -> Bool {
        defaults.string(forKey: PrefKeys.cipheredPin.rawValue) != nil
    }
}

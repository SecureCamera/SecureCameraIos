//
//  FileBasedSettingsDataSource.swift
//  SnapSafe
//
//  Created by Claude on 9/23/25.
//

import Foundation
import Combine
import Logging

// MARK: - File-based Settings Data Structure

private struct SettingsData: Codable {
    var hasCompletedIntro: Bool?
    var sanitizeFileName: Bool
    var sanitizeMetadata: Bool
    var sessionTimeoutMs: Int64
    var cipheredPin: String?
    var failedPinAttempts: Int
    var lastFailedAttempt: Int64
    var poisonPillPlain: String?
    var poisonPillHashed: String?
}

// MARK: - File-based Implementation

final class FileBasedSettingsDataSource: SettingsDataSource, @unchecked Sendable {
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

    // MARK: - Thread Safety
    private let queue = DispatchQueue(label: "com.snapsafe.settings", qos: .utility, attributes: .concurrent)
    private nonisolated(unsafe) var _settingsData: SettingsData
    
    // MARK: - File Management
    private let fileURL: URL
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    // MARK: - Init
    /// - Parameter sanitizeFileNameDefault: Default value for sanitize file name setting
    /// - Parameter sanitizeMetadataDefault: Default value for sanitize metadata setting
    init(
        sanitizeFileNameDefault: Bool = Defaults.sanitizeFileName,
        sanitizeMetadataDefault: Bool = Defaults.sanitizeMetadata,
        fileURL: URL? = nil
    ) {
        self.sanitizeFileNameDefault = sanitizeFileNameDefault
        self.sanitizeMetadataDefault = sanitizeMetadataDefault
        self.fileURL = fileURL ?? Self.getNonBackedUpSettingsURL()
        
        // Create initial settings data with defaults
        let defaultSettings = SettingsData(
            hasCompletedIntro: nil, // nil means not completed
            sanitizeFileName: sanitizeFileNameDefault,
            sanitizeMetadata: sanitizeMetadataDefault,
            sessionTimeoutMs: Defaults.sessionTimeoutMs,
            cipheredPin: nil,
            failedPinAttempts: 0,
            lastFailedAttempt: 0,
            poisonPillPlain: nil,
            poisonPillHashed: nil
        )

        // Load existing settings or use defaults
        self._settingsData = Self.loadSettingsFromFile(url: self.fileURL, defaults: defaultSettings)
        Logger.storage.debug("FileBasedSettingsDataSource initialized", metadata: [
            "fileURL": .string(self.fileURL.path),
            "hasExistingPin": .stringConvertible(_settingsData.cipheredPin != nil)
        ])
        
        // Initialize subjects from loaded values
        let introStored = _settingsData.hasCompletedIntro ?? false
        self.hasCompletedIntroSubject = .init(introStored)
        self.sanitizeFileNameSubject = .init(_settingsData.sanitizeFileName)
        self.sanitizeMetadataSubject = .init(_settingsData.sanitizeMetadata)
        self.sessionTimeoutSubject = .init(_settingsData.sessionTimeoutMs)
        
        // Ensure the file is saved with any missing defaults
        saveSettingsToFile()
    }

    // MARK: - File URL Helper
    private static func getNonBackedUpSettingsURL() -> URL {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        
        // Ensure the app support directory exists
        try? FileManager.default.createDirectory(at: appSupportPath, withIntermediateDirectories: true)
        
        var settingsFile = appSupportPath.appendingPathComponent("AppSettings.json")
        
        // Exclude from backup
        do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try settingsFile.setResourceValues(resourceValues)
            Logger.storage.debug("Settings file excluded from backup", metadata: [
                "fileURL": .string(settingsFile.path)
            ])
        } catch {
            Logger.storage.warning("Failed to exclude settings from backup", metadata: [
                "error": .string(error.localizedDescription),
                "fileURL": .string(settingsFile.path)
            ])
        }
        
        return settingsFile
    }
    
    // MARK: - File I/O
    private static func loadSettingsFromFile(url: URL, defaults: SettingsData) -> SettingsData {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let settings = try decoder.decode(SettingsData.self, from: data)
            Logger.storage.debug("Settings loaded from file", metadata: [
                "fileURL": .string(url.path),
                "fileSize": .stringConvertible(data.count)
            ])
            return settings
        } catch {
            if (error as NSError).code == NSFileReadNoSuchFileError {
                Logger.storage.debug("Settings file not found, using defaults", metadata: [
                    "fileURL": .string(url.path)
                ])
            } else {
                Logger.storage.warning("Failed to load settings file, using defaults", metadata: [
                    "error": .string(error.localizedDescription),
                    "fileURL": .string(url.path)
                ])
            }
            return defaults
        }
    }
    
    private func saveSettingsToFile() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            do {
                let data = try self.jsonEncoder.encode(self._settingsData)
                // Complete file protection: the settings file holds the
                // reversible poison-pill PIN ciphertext and the PIN hashes, so it
                // must be unreadable while the device is locked, not merely
                // excluded from backup (H2, Option D).
                try data.write(to: self.fileURL, options: [.atomic, .completeFileProtection])
                Logger.storage.debug("Settings saved to file", metadata: [
                    "fileURL": .string(self.fileURL.path),
                    "fileSize": .stringConvertible(data.count)
                ])
            } catch {
                Logger.storage.error("Failed to save settings to file", metadata: [
                    "error": .string(error.localizedDescription),
                    "fileURL": .string(self.fileURL.path)
                ])
            }
        }
    }
    
    // MARK: - Thread-Safe Property Access
    private func readProperty<T>(_ keyPath: KeyPath<SettingsData, T>) -> T {
        return queue.sync {
            return _settingsData[keyPath: keyPath]
        }
    }
    
    private func writeProperty<T>(_ keyPath: WritableKeyPath<SettingsData, T>, value: T) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._settingsData[keyPath: keyPath] = value
            self.saveSettingsToFile()
        }
    }

    // MARK: - Keys & PIN
    func getCipheredPin() async -> String? {
        return readProperty(\.cipheredPin)
    }

    func setIntroCompleted(_ completed: Bool) async {
        writeProperty(\.hasCompletedIntro, value: completed)
        await MainActor.run {
            hasCompletedIntroSubject.send(completed)
        }
    }

    func setAppPin(cipheredPin: String) async {
        writeProperty(\.cipheredPin, value: cipheredPin)
    }

    // MARK: - Sanitize prefs
    func setSanitizeFileName(_ sanitize: Bool) async {
        writeProperty(\.sanitizeFileName, value: sanitize)
        await MainActor.run {
            sanitizeFileNameSubject.send(sanitize)
        }
    }

    func setSanitizeMetadata(_ sanitize: Bool) async {
        writeProperty(\.sanitizeMetadata, value: sanitize)
        await MainActor.run {
            sanitizeMetadataSubject.send(sanitize)
        }
    }

    // MARK: - Failed PIN attempts
    func getFailedPinAttempts() async -> Int {
        return readProperty(\.failedPinAttempts)
    }

    func setFailedPinAttempts(_ count: Int) async {
        writeProperty(\.failedPinAttempts, value: count)
    }

    func incrementFailedPinAttempts() async -> Int {
        // Read-modify-write inside a single barrier block so the increment is atomic
        // with respect to every other access on the queue; concurrent callers can't
        // observe the same starting value and lose an increment.
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(returning: 0)
                    return
                }
                let newCount = self._settingsData.failedPinAttempts + 1
                self._settingsData.failedPinAttempts = newCount
                self.saveSettingsToFile()
                continuation.resume(returning: newCount)
            }
        }
    }

    func getLastFailedAttemptTimestamp() async -> Int64 {
        return readProperty(\.lastFailedAttempt)
    }

    func setLastFailedAttemptTimestamp(_ timestamp: Int64) async {
        writeProperty(\.lastFailedAttempt, value: timestamp)
    }

    // MARK: - Security reset
    func securityFailureReset() async {
        return await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                Logger.storage.warning("Performing security failure reset", metadata: [
                    "fileURL": .string(self.fileURL.path)
                ])
                
                // Reset to defaults
                self._settingsData = SettingsData(
                    hasCompletedIntro: nil,
                    sanitizeFileName: self.sanitizeFileNameDefault,
                    sanitizeMetadata: self.sanitizeMetadataDefault,
                    sessionTimeoutMs: self._settingsData.sessionTimeoutMs, // Preserve session timeout
                    cipheredPin: nil,
                    failedPinAttempts: 0,
                    lastFailedAttempt: 0,
                    poisonPillPlain: nil,
                    poisonPillHashed: nil
                )
                
                self.saveSettingsToFile()
                
                // Emit changes on main actor
                Task { @MainActor in
                    self.hasCompletedIntroSubject.send(false)
                    self.sanitizeFileNameSubject.send(self.sanitizeFileNameDefault)
                    self.sanitizeMetadataSubject.send(self.sanitizeMetadataDefault)
                    Logger.storage.info("Security failure reset completed")
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Session timeout
    func getSessionTimeout() async -> Int64 {
        return readProperty(\.sessionTimeoutMs)
    }

    func setSessionTimeout(_ timeoutMs: Int64) async {
        writeProperty(\.sessionTimeoutMs, value: timeoutMs)
        await MainActor.run {
            sessionTimeoutSubject.send(timeoutMs)
        }
    }
    
    // MARK: - Poison Pill
    func setPoisonPillPin(cipheredHashedPin: String, cipheredPlainPin: String) async {
        return await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._settingsData.poisonPillHashed = cipheredHashedPin
                self._settingsData.poisonPillPlain = cipheredPlainPin
                self.saveSettingsToFile()
                continuation.resume()
            }
        }
    }

    func getPlainPoisonPillPin() async -> String? {
        return readProperty(\.poisonPillPlain)
    }

    func getHashedPoisonPillPin() async -> String? {
        return readProperty(\.poisonPillHashed)
    }

    func activatePoisonPill(ciphered: String) async {
        writeProperty(\.cipheredPin, value: ciphered)
    }

    func removePoisonPillPin() async {
        return await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self._settingsData.poisonPillPlain = nil
                self._settingsData.poisonPillHashed = nil
                self.saveSettingsToFile()
                continuation.resume()
            }
        }
    }

    // periphery:ignore
    func isPinCiphered() async -> Bool {
        return readProperty(\.cipheredPin) != nil
    }
}

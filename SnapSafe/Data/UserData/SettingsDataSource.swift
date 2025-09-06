//
//  SettingsDataSource.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/2/25.
//

import Foundation
import Combine
import Mockable


@Mockable
public protocol SettingsDataSource {
    // MARK: - Intro state
    /// Check if the user has completed the introduction
    var hasCompletedIntro: AnyPublisher<Bool, Never> { get }

    // MARK: - Sanitize file name
    /// Get the sanitized file name preference
    var sanitizeFileName: AnyPublisher<Bool, Never> { get }
    var sanitizeFileNameDefault: Bool { get }

    // MARK: - Sanitize metadata
    /// Get the sanitized metadata preference
    var sanitizeMetadata: AnyPublisher<Bool, Never> { get }
    var sanitizeMetadataDefault: Bool { get }

    // MARK: - Session timeout
    /// Get the session timeout preference
    var sessionTimeout: AnyPublisher<Int64, Never> { get }
    
    // MARK: - Keys & PIN
    func getCipherKey() async -> String
    func getCipheredPin() async -> String?

    /// Set the introduction completion status
    func setIntroCompleted(_ completed: Bool) async

    /// Set the app PIN
    func setAppPin(cipheredPin: String) async

    /// Set the sanitize file name preference
    func setSanitizeFileName(_ sanitize: Bool) async

    /// Set the sanitize metadata preference
    func setSanitizeMetadata(_ sanitize: Bool) async

    // MARK: - Failed PIN attempts
    /// Get the current failed PIN attempts count
    func getFailedPinAttempts() async -> Int

    /// Set the failed PIN attempts count
    func setFailedPinAttempts(_ count: Int) async

    /// Get the current timestamp of the last failed PIN attempt
    func getLastFailedAttemptTimestamp() async -> Int64

    /// Set the timestamp of the last failed PIN attempt
    func setLastFailedAttemptTimestamp(_ timestamp: Int64) async

    // MARK: - Security reset
    /// Resets all user data and preferences when a security failure occurs.
    /// This deletes all stored preferences including PIN, intro completion status, and security settings.
    func securityFailureReset() async
    
    // MARK: - Session timeout (direct access)
    /// Get the current session timeout value
    func getSessionTimeout() async -> Int64

    /// Set the session timeout value
    func setSessionTimeout(_ timeoutMs: Int64) async

    // MARK: - Poison Pill
    /// Set the Poison Pill PIN
    func setPoisonPillPin(cipheredHashedPin: String, cipheredPlainPin: String) async

    func getPlainPoisonPillPin() async -> String?

    /// Get the hashed Poison Pill PIN
    func getHashedPoisonPillPin() async -> String?

    /// Activate the Poison Pill - replaces the regular PIN with the Poison Pill PIN
    func activatePoisonPill(ciphered: String) async

    /// Remove the Poison Pill PIN
    func removePoisonPillPin() async

    func isPinCiphered() async -> Bool
}

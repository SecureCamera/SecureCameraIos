//
//  AuthManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/3/25.
//

import LocalAuthentication
import UIKit

// class AuthenticationManager {
//    enum AuthMethod {
//        case devicePIN
//        case biometric
//        case appPIN
//    }
//
//    private let userDefaults = UserDefaults.standard
//    private let bioEnabledKey = "biometricAuthEnabled"
//    private let appPINKey = "appPIN"
//    private let poisonPINKey = "poisonPIN"
//
//    // Default to device PIN only
//    var isBiometricEnabled: Bool {
//        get { userDefaults.bool(forKey: bioEnabledKey) }
//        set { userDefaults.set(newValue, forKey: bioEnabledKey) }
//    }
//
//    // Set up app-specific PIN
//    func setAppPIN(_ pin: String) {
//        // In a real implementation, we would hash this PIN
//        // and store it securely in the keychain
//        let hashedPIN = hashPIN(pin)
//        userDefaults.set(hashedPIN, forKey: appPINKey)
//    }
//
//    // Set up poison pill PIN
//    func setPoisonPIN(_ pin: String) {
//        let hashedPIN = hashPIN(pin)
//        userDefaults.set(hashedPIN, forKey: poisonPINKey)
//    }
//
//    private func hashPIN(_ pin: String) -> String {
//        // In a real implementation, use a secure hashing function
//        // with salt and proper key derivation
//        return pin // Placeholder for actual implementation
//    }
//
//    func authenticate(withMethod method: AuthMethod, pin: String? = nil, completion: @escaping (Bool) -> Void) {
//        switch method {
//        case .devicePIN:
//            authenticateWithDevicePIN(completion: completion)
//        case .biometric:
//            if isBiometricEnabled {
//                authenticateWithBiometrics(completion: completion)
//            } else {
//                completion(false)
//            }
//        case .appPIN:
//            guard let inputPIN = pin else {
//                completion(false)
//                return
//            }
//
//            let hashedInputPIN = hashPIN(inputPIN)
//            let storedPIN = userDefaults.string(forKey: appPINKey) ?? ""
//            let poisonPIN = userDefaults.string(forKey: poisonPINKey) ?? ""
//
//            if hashedInputPIN == poisonPIN {
//                // Trigger poison pill functionality
//                do {
//                    let secureFileManager = SecureFileManager()
//                    try secureFileManager.deleteAllPhotos()
//                    completion(false) // Don't grant access
//                } catch {
//                    completion(false)
//                }
//            } else {
//                completion(hashedInputPIN == storedPIN)
//            }
//        }
//    }
//
//    private func authenticateWithDevicePIN(completion: @escaping (Bool) -> Void) {
//        let context = LAContext()
//        var error: NSError?
//
//        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
//            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to access secure photos") { success, error in
//                DispatchQueue.main.async {
//                    completion(success)
//                }
//            }
//        } else {
//            completion(false)
//        }
//    }
//
//    private func authenticateWithBiometrics(completion: @escaping (Bool) -> Void) {
//        let context = LAContext()
//        var error: NSError?
//
//        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
//            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to access secure photos") { success, error in
//                DispatchQueue.main.async {
//                    completion(success)
//                }
//            }
//        } else {
//            completion(false)
//        }
//    }
// }

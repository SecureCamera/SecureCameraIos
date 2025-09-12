//
//  VerifyPinUseCase.swift
//  SnapSafe
//
//  Created by Claude on 9/11/25.
//

import Foundation
import Logging

public final class VerifyPinUseCase {
    private let authManager: AuthorizationRepository
    private let imageManager: SecureImageRepository
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    private let authorizePinUseCase: AuthorizePinUseCase
    
    public init(
        authManager: AuthorizationRepository,
        imageManager: SecureImageRepository,
        pinRepository: PinRepository,
        encryptionScheme: EncryptionScheme,
        authorizePinUseCase: AuthorizePinUseCase
    ) {
        self.authManager = authManager
        self.imageManager = imageManager
        self.pinRepository = pinRepository
        self.encryptionScheme = encryptionScheme
        self.authorizePinUseCase = authorizePinUseCase
    }
    
    /// Verifies a PIN and handles poison pill activation if detected
    /// - Parameter pin: The PIN to verify
    /// - Returns: `true` if PIN verification succeeded, `false` otherwise
    public func verifyPin(_ pin: String) async -> Bool {
        do {
            // Check for poison pill PIN first
            let hasPoison = try await pinRepository.hasPoisonPillPin()
            let isPoison  = await pinRepository.verifyPoisonPillPin(pin)
            
            // Check for poison pill PIN first
            if hasPoison && isPoison {
                Logger.security.warning("Poison pill PIN detected - activating poison pill mode")
                
                // Get the old hashed PIN before activating poison pill
                let oldHashedPin = await pinRepository.getHashedPin()
                
                // Activate poison pill across all components
                encryptionScheme.activatePoisonPill(oldPin: oldHashedPin)
                await imageManager.activatePoisonPill()
                await pinRepository.activatePoisonPill()
                
                Logger.security.info("Poison pill mode activated successfully")
            }
            
            // Attempt regular PIN authorization
            let hashedPin = await authorizePinUseCase.authorizePin(pin)
            guard let hashedPin else {
                Logger.security.warning("PIN verification failed - invalid PIN provided")
                return false
            }

            try! await encryptionScheme.deriveAndCacheKey(plainPin: pin, hashedPin: hashedPin)
            Logger.security.info("PIN verification successful")
            return true
        } catch {
            Logger.security.error("PIN verification failed with error", metadata: [
                "error": .string(String(describing: error))
            ])
            return false
        }
    }
}

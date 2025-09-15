//
//  VerifyPinUseCase.swift
//  SnapSafe
//
//  Created by Claude on 9/11/25.
//

import Foundation
import Logging

public final class VerifyPinUseCase {
    private let authRepo: AuthorizationRepository
    private let imageRepo: SecureImageRepository
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    private let authorizePinUseCase: AuthorizePinUseCase
    
    public init(
        authRepository: AuthorizationRepository,
        imageRepository: SecureImageRepository,
        pinRepository: PinRepository,
        encryptionScheme: EncryptionScheme,
        authorizePinUseCase: AuthorizePinUseCase
    ) {
        self.authRepo = authRepository
        self.imageRepo = imageRepository
        self.pinRepository = pinRepository
        self.encryptionScheme = encryptionScheme
        self.authorizePinUseCase = authorizePinUseCase
    }
    
    /// Verifies a PIN and handles poison pill activation if detected
    /// - Parameter pin: The PIN to verify
    /// - Returns: `true` if PIN verification succeeded, `false` otherwise
    public func verifyPin(_ pin: String) async -> Bool {
        // Check for poison pill PIN first
        let hasPoison = await pinRepository.hasPoisonPillPin()
        let isPoison  = await pinRepository.verifyPoisonPillPin(pin)
        
        // Check for poison pill PIN first
        if hasPoison && isPoison {
            Logger.security.warning("Poison pill PIN detected - activating poison pill mode")
            
            // Get the old hashed PIN before activating poison pill
            let oldHashedPin = await pinRepository.getHashedPin()
            
            // Activate poison pill across all components
            encryptionScheme.activatePoisonPill(oldPin: oldHashedPin)
            await imageRepo.activatePoisonPill()
            await pinRepository.activatePoisonPill()
            
            Logger.security.info("Poison pill mode activated successfully")
        }
        
        // Attempt regular PIN authorization
        let hashedPin = await authorizePinUseCase.authorizePin(pin)
        guard let hashedPin else {
            _ = await authRepo.incrementFailedAttempts()
            Logger.security.warning("PIN verification failed - invalid PIN provided")
            return false
        }

        try! await encryptionScheme.deriveAndCacheKey(plainPin: pin, hashedPin: hashedPin)
        Logger.security.info("PIN verification successful")
        return true
    }
}

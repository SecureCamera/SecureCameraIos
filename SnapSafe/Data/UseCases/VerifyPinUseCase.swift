//
//  VerifyPinUseCase.swift
//  SnapSafe
//
//  Created by Claude on 9/11/25.
//

import Foundation
import Logging

/// Outcome of a PIN verification attempt.
///
/// `failure` is reserved for transient, retryable errors (e.g. I/O while reading
/// the wrapped DEK, or `errSecInteractionNotAllowed` if the device locks mid-flow).
/// It is intentionally distinct from `invalidPin` so the UI can offer a retry
/// without burning a failed-attempt against the user.
enum PinVerificationResult: Sendable {
    case success
    /// The PIN did not match. Carries the authoritative post-increment failed
    /// attempt count from the repository (the single writer), so the caller
    /// never re-derives or re-writes it from stale local state (M1).
    case invalidPin(failedAttempts: Int)
    case failure(Error)
}

final class VerifyPinUseCase: @unchecked Sendable {
    private let authRepo: AuthorizationRepository
    private let imageRepo: SecureImageRepository
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    private let authorizePinUseCase: AuthorizePinUseCase
    
    init(
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
    
    /// Verifies a PIN and handles poison pill activation if detected.
    /// - Parameter pin: The PIN to verify.
    /// - Returns: `.success` when the PIN is correct and the key is derived and cached,
    ///   `.invalidPin` when the PIN does not match, or `.failure(error)` when a
    ///   transient/retryable error occurs (e.g. key derivation I/O or hardware
    ///   transient failure). Callers should surface `.failure` as a retryable error
    ///   without counting it as a failed attempt.
    func verifyPin(_ pin: String) async -> PinVerificationResult {
        // Check for poison pill PIN first. Short-circuit on hasPoisonPillPin
        // so we don't run a second Argon2 verification each attempt and don't
        // leak a timing oracle revealing whether a poison pill is configured.
        if await pinRepository.hasPoisonPillPin(),
           await pinRepository.verifyPoisonPillPin(pin) {
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
            // Single writer: the repository owns the counter and the backoff
            // timestamp/baseline. Return the authoritative new count so the
            // caller displays it without writing it a second time (M1).
            let failedAttempts = await authRepo.incrementFailedAttempts()
            Logger.security.warning("PIN verification failed - invalid PIN provided")
            return .invalidPin(failedAttempts: failedAttempts)
        }

        do {
            try await encryptionScheme.deriveAndCacheKey(plainPin: pin, hashedPin: hashedPin)
        } catch {
            Logger.security.error("Key derivation failed after valid PIN", metadata: [
                "error": .string(String(describing: error))
            ])
            return .failure(error)
        }

        Logger.security.info("PIN verification successful")
        return .success
    }
}

//
//  CreatePinUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/4/25.
//

import Logging


public final class CreatePinUseCase: @unchecked Sendable {
    private let authorizationRepository: AuthorizationRepository
    private let encryptionScheme: EncryptionScheme
    private let pinRepository: PinRepository
    private let settingsDataSource: SettingsDataSource
    private let authorizePinUseCase: AuthorizePinUseCase

    public init(
        authorizationRepository: AuthorizationRepository,
        encryptionScheme: EncryptionScheme,
        pinRepository: PinRepository,
        settingsDataSource: SettingsDataSource,
        authorizePinUseCase: AuthorizePinUseCase
    ) {
        self.authorizationRepository = authorizationRepository
        self.encryptionScheme = encryptionScheme
        self.pinRepository = pinRepository
        self.settingsDataSource = settingsDataSource
        self.authorizePinUseCase = authorizePinUseCase
    }

    /// Creates a PIN, immediately authorizes it, and on success:
    /// 1) creates the key, 2) derives & caches encryption key, 3) marks intro complete.
    /// - Returns: `true` on success, `false` otherwise.
    public func createPin(_ pin: String) async -> Bool {
        do {
            await pinRepository.setAppPin(pin)

            let hashedPin = await authorizePinUseCase.authorizePin(pin)
            guard let hashedPin else { return false }

            _ = await authorizationRepository.createKey(pin: pin, hashedPin: hashedPin)
            try await encryptionScheme.deriveAndCacheKey(plainPin: pin, hashedPin: hashedPin)
            await settingsDataSource.setIntroCompleted(true)
            return true
        } catch {
            // Log the error for debugging purposes
            Logger.security.error("Failed to create PIN", metadata: [
                "error": .string(String(describing: error))
            ])
            return false
        }
    }
}

//
//  CreatePoisonPillUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/11/25.
//

import Logging

final class CreatePoisonPillUseCase: @unchecked Sendable {
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    
    init(pinRepository: PinRepository, encryptionScheme: EncryptionScheme) {
        self.pinRepository = pinRepository
        self.encryptionScheme = encryptionScheme
    }
    
    func createPin(pppin: String) async -> Bool {
        await pinRepository.setPoisonPillPin(pppin)
        guard let hashedPPPin = await pinRepository.getHashedPoisonPillPin() else {
            Logger.security.error("Failed to retrieve hashed poison pill pin")
            return false
        }

        do {
            try await encryptionScheme.createKey(plainPin: pppin, hashedPin: hashedPPPin)
        } catch {
            Logger.security.error("Failed to create poison pill key: \(error)")
            return false
        }

        return true
    }
}

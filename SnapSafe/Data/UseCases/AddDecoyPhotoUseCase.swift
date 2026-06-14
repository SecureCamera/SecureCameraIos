//
//  AddDecoyPhotoUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation
import FactoryKit
import Logging


final class AddDecoyPhotoUseCase: @unchecked Sendable {
    private let pinRepository: PinRepository
    private let encryptionScheme: EncryptionScheme
    private let imageRepository: SecureImageRepository

    init(
        pinRepository: PinRepository,
        encryptionScheme: EncryptionScheme,
        imageRepository: SecureImageRepository
    ) {
        self.pinRepository = pinRepository
        self.encryptionScheme = encryptionScheme
        self.imageRepository = imageRepository
    }

    func addDecoyPhoto(photoDef: PhotoDef) async -> Bool {
        // Enforce the decoy limit BEFORE any cryptographic work: at the limit we
        // must not read the plaintext poison-pill PIN or derive a key.
        guard await imageRepository.numDecoys() < SecureImageRepository.maxDecoyItems else {
            return false
        }

        guard
            let ppp = await pinRepository.getHashedPoisonPillPin(),
            let plain = await pinRepository.getPlainPoisonPillPin()
        else {
            return false
        }

        // If deriveKey can throw, handle here; otherwise drop `try`/`do-catch`.
        let keyBytes: Data
        do {
            keyBytes = try await encryptionScheme.deriveKey(plainPin: plain, hashedPin: ppp)
        } catch {
            Logger.security.error("Failed to derive key for Poison Pill setting decoy: \(error)")
            return false
        }

        return await imageRepository.addDecoyPhotoWithKey(photoDef, keyData: keyBytes)
    }
}

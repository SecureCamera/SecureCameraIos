//
//  AddDecoyPhotoUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation
import FactoryKit


final class AddDecoyPhotoUseCase {
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
            return false
        }

        return try! await imageRepository.addDecoyPhotoWithKey(photoDef, keyData: keyBytes)
    }
}

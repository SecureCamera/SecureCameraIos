//
//  AddDecoyVideoUseCase.swift
//  SnapSafe
//

import Foundation
import FactoryKit
import Logging


/// Marks a video as a decoy. Mirrors `AddDecoyPhotoUseCase`: it derives the
/// poison-pill key and asks the repository to re-encrypt the video with it so
/// the decoy survives (and stays playable) after the poison pill is activated.
final class AddDecoyVideoUseCase: @unchecked Sendable {
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

    func addDecoyVideo(videoDef: VideoDef) async -> Bool {
        // Enforce the decoy limit BEFORE any cryptographic work: at the limit we
        // must not read the plaintext poison-pill PIN or derive a key. The limit
        // is shared across photos and videos (numDecoys() counts both).
        guard await imageRepository.numDecoys() < SecureImageRepository.maxDecoyItems else {
            return false
        }

        guard
            let ppp = await pinRepository.getHashedPoisonPillPin(),
            let plain = await pinRepository.getPlainPoisonPillPin()
        else {
            return false
        }

        let keyBytes: Data
        do {
            keyBytes = try await encryptionScheme.deriveKey(plainPin: plain, hashedPin: ppp)
        } catch {
            Logger.security.error("Failed to derive key for Poison Pill setting decoy video: \(error)")
            return false
        }

        return await imageRepository.addDecoyVideoWithKey(videoDef, keyData: keyBytes)
    }
}

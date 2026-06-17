//
//  SecurityResetUseCase.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/8/25.
//

import Foundation
import Logging

final class SecurityResetUseCase: @unchecked Sendable {
    private let authRepo: AuthorizationRepository
    private let imageRepository: SecureImageRepository
    private let encryptionScheme: EncryptionScheme

    /// Delete any stranded unencrypted .mov files left from interrupted recordings.
    /// Call this on app startup to ensure no plaintext video data persists.
    static func cleanupStrandedTempVideos() {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let videosDir = appSupportPath.appendingPathComponent("videos")

        guard FileManager.default.fileExists(atPath: videosDir.path) else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)
            let movFiles = files.filter { $0.pathExtension.lowercased() == "mov" }
            for file in movFiles {
                try FileManager.default.removeItem(at: file)
                Logger.security.info("Deleted stranded temp video", metadata: [
                    "file": .string(file.lastPathComponent)
                ])
            }
        } catch {
            Logger.security.error("Failed to clean up temp videos", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    init(
        authManager: AuthorizationRepository,
        imageRepository: SecureImageRepository,
        encryptionScheme: EncryptionScheme
    ) {
        self.authRepo = authManager
        self.imageRepository = imageRepository
        self.encryptionScheme = encryptionScheme
    }
    
    func reset() async {
        await authRepo.securityFailureReset()
        await imageRepository.securityFailureReset()
        await encryptionScheme.securityFailureReset()
        deleteAllVideos()
        Logger.security.info("Security Reset Complete!")
    }

    /// Delete all video files (both temp .mov and encrypted .secv).
    private func deleteAllVideos() {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let videosDir = appSupportPath.appendingPathComponent("videos")

        guard FileManager.default.fileExists(atPath: videosDir.path) else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            Logger.security.info("Deleted all video files during security reset", metadata: [
                "count": .stringConvertible(files.count)
            ])
        } catch {
            Logger.security.error("Failed to delete video files during security reset", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
}

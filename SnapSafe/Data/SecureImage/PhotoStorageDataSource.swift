//
//  PhotoStorageDataSource.swift
//  SnapSafe
//
//  Stateless storage layer for encrypted media: owns the on-disk directory
//  layout (with backup exclusion) and raw encrypt-to-file / decrypt-from-file
//  operations. SecureImageRepository delegates all filesystem + crypto-at-rest
//  work here and keeps the domain logic.
//

import Foundation
import Logging

struct PhotoStorageDataSource {

    // MARK: - Directory names (single source of truth)

    static let photosDir = "photos"
    static let decoysDir = "decoys"
    static let videosDir = "videos"
    static let videoThumbnailsDir = "videoThumbnails"
    static let decoyVideoThumbnailsDir = "decoyVideoThumbnails"
    static let thumbnailsDir = ".thumbnails"

    // MARK: - Dependencies

    private let encryptionScheme: EncryptionScheme
    /// Roots every storage directory is derived from. Injected so hosted unit
    /// tests can point at a temp directory instead of the real app container.
    private let appSupportRoot: URL
    private let cachesRoot: URL

    init(encryptionScheme: EncryptionScheme, appSupportRoot: URL, cachesRoot: URL) {
        self.encryptionScheme = encryptionScheme
        self.appSupportRoot = appSupportRoot
        self.cachesRoot = cachesRoot
    }

    // MARK: - Directory Management

    func getGalleryDirectory() -> URL {
        var galleryDir = appSupportRoot.appendingPathComponent(Self.photosDir)

        // Create directory and exclude from backup
        do {
            try FileManager.default.createDirectory(at: galleryDir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try galleryDir.setResourceValues(resourceValues)
        } catch {
            Logger.storage.error("Failed to setup gallery directory: \(error)")
        }

        return galleryDir
    }

    func getDecoyDirectory() -> URL {
        var decoyDir = appSupportRoot.appendingPathComponent(Self.decoysDir)

        // Create directory and exclude from backup
        do {
            try FileManager.default.createDirectory(at: decoyDir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try decoyDir.setResourceValues(resourceValues)
        } catch {
            Logger.storage.error("Failed to setup decoy directory: \(error)")
        }

        return decoyDir
    }

    func getVideosDirectory() -> URL {
        var videosDir = appSupportRoot.appendingPathComponent(Self.videosDir)

        // Create directory and exclude from backup
        do {
            try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try videosDir.setResourceValues(resourceValues)
        } catch {
            Logger.storage.error("Failed to setup videos directory: \(error)")
        }

        return videosDir
    }

    /// Durable, encrypted storage for video thumbnails. Unlike photo thumbnails
    /// (regenerated from the encrypted photo on demand), video thumbnails are
    /// generated once at record time from the plaintext `.mov` and cannot be
    /// recreated afterwards, so they live in Application Support rather than the
    /// purgeable caches directory.
    func getVideoThumbnailsDirectory() -> URL {
        var dir = appSupportRoot.appendingPathComponent(Self.videoThumbnailsDir)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try dir.setResourceValues(resourceValues)
        } catch {
            Logger.storage.error("Failed to setup video thumbnails directory: \(error)")
        }

        return dir
    }

    /// Decoy video thumbnails: re-encrypted with the poison-pill key at mark time
    /// and restored into `videoThumbnails/` when the poison pill activates (the
    /// real-key thumbnails are destroyed then, so decoy videos would otherwise
    /// lose their thumbnail). Kept separate so it is not wiped by
    /// `deleteAllVideoThumbnails()` or the decoy directory cleanup.
    func getDecoyVideoThumbnailsDirectory() -> URL {
        var dir = appSupportRoot.appendingPathComponent(Self.decoyVideoThumbnailsDir)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try dir.setResourceValues(resourceValues)
        } catch {
            Logger.storage.error("Failed to setup decoy video thumbnails directory: \(error)")
        }

        return dir
    }

    func getThumbnailsDirectory() -> URL {
        let thumbnailsDir = cachesRoot.appendingPathComponent(Self.thumbnailsDir)

        if !FileManager.default.fileExists(atPath: thumbnailsDir.path) {
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        }

        return thumbnailsDir
    }

    // MARK: - Raw encrypted file I/O

    /// Encrypts and saves data to a file.
    func encryptToFile(_ data: Data, targetFile: URL) async throws {
        try await encryptionScheme.encryptToFile(plain: data, targetFile: targetFile)
        Logger.storage.info("Saved image to file: \(targetFile.path)")
    }

    /// Decrypts a file and returns the data.
    func decryptFile(_ encryptedFile: URL) async throws -> Data {
        return try await encryptionScheme.decryptFile(encryptedFile)
    }

    /// Encrypts data to a temp file, then atomically moves it to the target file.
    func encryptAndSaveImage(_ imageData: Data, tempFile: URL, targetFile: URL) async throws {
        // Remove files if they exist
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(at: targetFile)

        // Encrypt to temp file
        try await encryptToFile(imageData, targetFile: tempFile)

        // Move temp file to target
        try FileManager.default.moveItem(at: tempFile, to: targetFile)
    }

    // MARK: - File paths

    func getThumbnailFile(_ photoDef: PhotoDef) -> URL {
        return getThumbnailsDirectory().appendingPathComponent(photoDef.photoName)
    }

    func getDecoyFile(_ photoDef: PhotoDef) -> URL {
        return getDecoyDirectory().appendingPathComponent(photoDef.photoName)
    }

    func getDecoyVideoFile(_ videoDef: VideoDef) -> URL {
        return getDecoyDirectory().appendingPathComponent(videoDef.videoFile.lastPathComponent)
    }

    func getVideoThumbnailFile(forVideoNamed name: String) -> URL {
        return getVideoThumbnailsDirectory().appendingPathComponent(name).appendingPathExtension("jpg")
    }

    func getDecoyVideoThumbnailFile(forVideoNamed name: String) -> URL {
        return getDecoyVideoThumbnailsDirectory().appendingPathComponent(name).appendingPathExtension("jpg")
    }

    // MARK: - Decoy file enumeration

    /// Decoy photo files (`.jpg`) currently in the decoy directory.
    func getDecoyFiles() -> [URL] {
        let dir = getDecoyDirectory()

        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            return files.filter { $0.hasDirectoryPath == false && $0.pathExtension == "jpg" }
        } catch {
            return []
        }
    }

    /// Decoy video files (`.secv`) currently in the decoy directory.
    func getDecoyVideoFiles() -> [URL] {
        let dir = getDecoyDirectory()

        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            return files.filter { $0.hasDirectoryPath == false && $0.pathExtension.lowercased() == "secv" }
        } catch {
            return []
        }
    }
}

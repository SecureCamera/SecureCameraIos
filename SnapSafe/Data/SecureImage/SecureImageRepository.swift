//
//  SecureImageRepository.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import Foundation
import Logging
import UIKit
import CoreLocation
import UniformTypeIdentifiers
import ImageIO
import CryptoKit
import AVFoundation

@MainActor
class SecureImageRepository {
    
    // MARK: - Constants
    
    static let photosDir = "photos"
    static let decoysDir = "decoys"
    static let videosDir = "videos"
    static let videoThumbnailsDir = "videoThumbnails"
    static let decoyVideoThumbnailsDir = "decoyVideoThumbnails"
    static let thumbnailsDir = ".thumbnails"
    static let maxDecoyPhotos = 10
    
    // MARK: - Dependencies
    
    let thumbnailCache: ThumbnailCache
    private let encryptionScheme: EncryptionScheme
    private let videoEncryptionService: VideoEncryptionServiceProtocol

    /// Roots that every storage directory is derived from. They default to the
    /// real app container locations, but can be overridden (e.g. with a temp
    /// directory in tests) so that hosted unit tests never read from or write to
    /// the real app's data. Previously each getter recomputed these from
    /// `FileManager.default`, which meant tests that didn't subclass-override a
    /// specific getter would silently operate on the real container — deleting
    /// real, unrecoverable video thumbnails on poison-pill / security-reset.
    private let appSupportRoot: URL
    private let cachesRoot: URL

    // MARK: - Initialization

    init(
        thumbnailCache: ThumbnailCache,
        encryptionScheme: EncryptionScheme,
        videoEncryptionService: VideoEncryptionServiceProtocol = VideoEncryptionService(),
        applicationSupportDirectory: URL? = nil,
        cachesDirectory: URL? = nil
    ) {
        self.thumbnailCache = thumbnailCache
        self.encryptionScheme = encryptionScheme
        self.videoEncryptionService = videoEncryptionService
        self.appSupportRoot = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.cachesRoot = cachesDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
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

    private func getThumbnailsDirectory() -> URL {
        let thumbnailsDir = cachesRoot.appendingPathComponent(Self.thumbnailsDir)
        
        if !FileManager.default.fileExists(atPath: thumbnailsDir.path) {
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        }
        
        return thumbnailsDir
    }
    
    // MARK: - Security Operations
    
    func evictKey() async {
        await encryptionScheme.evictKey()
    }

    /// Resets all security-related data when a security failure occurs.
    /// Deletes all images and thumbnails and evicts all in-memory data.
    func securityFailureReset() async {
        deleteAllImages()
        deleteAllVideoThumbnails()
        deleteAllDecoyVideoThumbnails()
        clearAllThumbnails()
        await evictKey()
    }

    /// Deletes all images that haven't been flagged as benign
    func activatePoisonPill() async {
        // Delete non-decoy videos first, while the decoy directory is still
        // intact (deleteNonDecoyImages() consumes and removes that directory).
        deleteNonDecoyVideos()
        deleteNonDecoyImages()
        // Video thumbnails are derived from real video frames; destroy them all,
        // then restore the poison-pill-key thumbnails for the surviving decoy
        // videos so they still show a thumbnail in the gallery.
        deleteAllVideoThumbnails()
        restoreDecoyVideoThumbnails()
        clearAllThumbnails()
        await evictKey()
    }
    
    private func clearAllThumbnails() {
        let thumbnailsDir = getThumbnailsDirectory()
        do {
            try FileManager.default.removeItem(at: thumbnailsDir)
        } catch {
            Logger.storage.error("Failed to remove thumbnailsDir: \(error.localizedDescription)")
        }
        thumbnailCache.clear()
    }
    
    // MARK: - Image Operations
    
    /// Encrypts and saves image data to a file
    private func encryptToFile(_ data: Data, targetFile: URL) async throws {
        try await encryptionScheme.encryptToFile(plain: data, targetFile: targetFile)
        Logger.storage.info("Saved image to file: \(targetFile.path)")
    }
    
    /// Decrypts a file and returns the data
    private func decryptFile(_ encryptedFile: URL) async throws -> Data {
        return try await encryptionScheme.decryptFile(encryptedFile)
    }
    
    /// Encrypts and saves image data to a file, then renames it to the target file
    private func encryptAndSaveImage(_ imageData: Data, tempFile: URL, targetFile: URL) async throws {
        // Remove files if they exist
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(at: targetFile)
        
        // Encrypt to temp file
        try await encryptToFile(imageData, targetFile: tempFile)
        
        // Move temp file to target
        try FileManager.default.moveItem(at: tempFile, to: targetFile)
    }
    
    /// Saves a captured image to the gallery
    func saveImage(
        _ image: CapturedImage,
        location: CLLocation?,
        applyRotation: Bool,
        quality: CGFloat = 0.9
    ) async throws -> PhotoDef {
        let dir = getGalleryDirectory()
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        // Generate filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss_SS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let filename = "photo_\(dateFormatter.string(from: image.timestamp)).jpg"
        
        let photoFile = dir.appendingPathComponent(filename)
        let tempFile = dir.appendingPathComponent("\(filename).tmp")
        
        // Process image
        var processedImage = image.sensorBitmap
        if applyRotation {
            processedImage = ImageProcessing.rotateImage(image.sensorBitmap, degrees: image.rotationDegrees)
        }
        
        // Compress to JPEG
        guard let jpegData = ImageProcessing.compressImageToJpeg(processedImage, quality: quality) else {
            throw ImageRepositoryError.compressionFailed
        }
        
        // Apply metadata
        let updatedData = ImageProcessing.applyImageMetadata(jpegData, location: location, applyRotation: applyRotation, rotationDegrees: image.rotationDegrees)
        
        // Encrypt and save
        try await encryptAndSaveImage(updatedData, tempFile: tempFile, targetFile: photoFile)
        
        return PhotoDef(photoName: filename, photoFormat: "jpg", photoFile: photoFile)
    }
    
    /// Reads and decrypts an image file
    func readImage(_ photo: PhotoDef) async throws -> UIImage {
        let data = try await decryptFile(photo.photoFile)
        guard let image = UIImage(data: data) else {
            throw ImageRepositoryError.invalidImageData
        }
        return image
    }
    
    /// Decrypts and returns JPEG data
    func decryptJpg(_ photo: PhotoDef) async throws -> Data {
        return try await decryptFile(photo.photoFile)
    }
    
    // MARK: - Thumbnail Operations
    
    private func getThumbnailFile(_ photoDef: PhotoDef) -> URL {
        return getThumbnailsDirectory().appendingPathComponent(photoDef.photoName)
    }
    
    /// Reads or creates a thumbnail for the given photo
    func readThumbnail(_ photo: PhotoDef) async -> UIImage? {
        // Check cache first
        if let cachedThumbnail = thumbnailCache.getThumbnail(photo) {
            return cachedThumbnail
        }
        
        let thumbFile = getThumbnailFile(photo)
        var thumbnailImage: UIImage?
        
        if FileManager.default.fileExists(atPath: thumbFile.path) {
            // Decrypt existing thumbnail
            do {
                let data = try await decryptFile(thumbFile)
                thumbnailImage = UIImage(data: data)
            } catch {
                Logger.storage.error("Failed to decrypt thumbnail", metadata: [
                    "photoName": .string(photo.photoName),
                    "error": .string(String(describing: error))
                ])
                return nil
            }
        } else if FileManager.default.fileExists(atPath: photo.photoFile.path) {
            // Create thumbnail from full image
            do {
                let data = try await decryptFile(photo.photoFile)
                guard let fullImage = UIImage(data: data) else { return nil }
                
                // Create smaller thumbnail
                let thumbnailSize = CGSize(width: fullImage.size.width / 4, height: fullImage.size.height / 4)
                thumbnailImage = ImageProcessing.resizeImage(fullImage, to: thumbnailSize)
                
                // Cache thumbnail to file
                if let thumbnailImage = thumbnailImage,
                   let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.75) {
                    try await encryptToFile(thumbnailData, targetFile: thumbFile)
                }
            } catch {
                Logger.storage.error("Failed to create thumbnail", metadata: [
                    "photoName": .string(photo.photoName),
                    "error": .string(String(describing: error))
                ])
                return nil
            }
        }
        
        // Cache in memory
        if let thumbnailImage = thumbnailImage {
            thumbnailCache.putThumbnail(photo, thumbnailImage)
        }
        
        return thumbnailImage
    }
    
    // MARK: - Photo Management
    
    /// Gets all photos in the gallery
    func getPhotos() -> [PhotoDef] {
        let dir = getGalleryDirectory()
        
        guard FileManager.default.fileExists(atPath: dir.path) else {
            return []
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            return files
                .filter { $0.hasDirectoryPath == false }
                .map { file in
                    let name = file.lastPathComponent
                    let format = file.pathExtension.isEmpty ? "jpg" : file.pathExtension
                    return PhotoDef(photoName: name, photoFormat: format, photoFile: file)
                }
                .sorted { $0.photoName > $1.photoName } // Sort by name (newest first)
        } catch {
            Logger.storage.error("Failed to get photos", metadata: [
                "directory": .string(dir.path),
                "error": .string(String(describing: error))
            ])
            return []
        }
    }
    
    /// Deletes a single image
    @discardableResult
    func deleteImage(_ photoDef: PhotoDef, deleteDecoy: Bool = true) -> Bool {
        thumbnailCache.evictThumbnail(photoDef)
        
        if deleteDecoy && isDecoyPhoto(photoDef) {
            try? FileManager.default.removeItem(at: getDecoyFile(photoDef))
        }
        
        let thumbnailFile = getThumbnailFile(photoDef)
        try? FileManager.default.removeItem(at: thumbnailFile)
        
        if FileManager.default.fileExists(atPath: photoDef.photoFile.path) {
            do {
                try FileManager.default.removeItem(at: photoDef.photoFile)
                return true
            } catch {
                return false
            }
        }
        
        return false
    }
    
    /// Deletes multiple images
    @discardableResult
    func deleteImages(_ photos: [PhotoDef], deleteDecoy: Bool = true) -> Bool {
        return photos.allSatisfy { deleteImage($0, deleteDecoy: deleteDecoy) }
    }
    
    /// Deletes all images
    func deleteAllImages(deleteDecoy: Bool = true) {
        let photos = getPhotos()
        deleteImages(photos, deleteDecoy: deleteDecoy)
    }
    
    /// Deletes all non-decoy images and restores decoys
    func deleteNonDecoyImages() {
        let galleryDir = getGalleryDirectory()
        let thumbnailsDir = getThumbnailsDirectory()
        
        // Remove all current images and thumbnails
        try? FileManager.default.removeItem(at: galleryDir)
        try? FileManager.default.removeItem(at: thumbnailsDir)
        
        // Recreate directories
        try? FileManager.default.createDirectory(at: galleryDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        
        // Move decoy files back to gallery
        let decoyFiles = getDecoyFiles()
        for file in decoyFiles {
            let targetFile = galleryDir.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.moveItem(at: file, to: targetFile)
        }
        
        // Remove decoy directory
        try? FileManager.default.removeItem(at: getDecoyDirectory())
    }

    /// Destroys every video that hasn't been flagged as a decoy, and replaces
    /// each decoy video with its decoy copy.
    ///
    /// A decoy video is stored in the decoy directory re-encrypted with the
    /// poison-pill key (the original in the videos directory is encrypted with
    /// the real key, which the poison pill destroys). So for decoy videos we
    /// move the decoy copy into the videos directory, overwriting the original.
    ///
    /// Must run before `deleteNonDecoyImages()`, which removes the decoy
    /// directory this relies on.
    private func deleteNonDecoyVideos() {
        let videosDir = getVideosDirectory()
        let decoyVideoFiles = getDecoyVideoFiles()
        let decoyVideoNames = Set(decoyVideoFiles.map { $0.lastPathComponent })

        // 1. Destroy every video that isn't a decoy.
        if let files = try? FileManager.default.contentsOfDirectory(at: videosDir, includingPropertiesForKeys: nil) {
            for file in files where !decoyVideoNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // 2. Replace each decoy video's original (real-key) file with its
        //    poison-pill-key copy from the decoy directory.
        for decoyFile in decoyVideoFiles {
            let target = videosDir.appendingPathComponent(decoyFile.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.moveItem(at: decoyFile, to: target)
        }
    }

    // MARK: - Decoy Operations
    
    private func getDecoyFile(_ photoDef: PhotoDef) -> URL {
        return getDecoyDirectory().appendingPathComponent(photoDef.photoName)
    }
    
    private func getDecoyFiles() -> [URL] {
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
    
    /// Checks if a photo is marked as decoy
    func isDecoyPhoto(_ photoDef: PhotoDef) -> Bool {
        return FileManager.default.fileExists(atPath: getDecoyFile(photoDef).path)
    }

    /// Gets the total number of decoys (photos + videos); the limit is shared.
    func numDecoys() -> Int {
        return getDecoyFiles().count + getDecoyVideoFiles().count
    }

    // MARK: - Decoy Video Operations

    private func getDecoyVideoFile(_ videoDef: VideoDef) -> URL {
        return getDecoyDirectory().appendingPathComponent(videoDef.videoFile.lastPathComponent)
    }

    private func getDecoyVideoFiles() -> [URL] {
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

    /// Checks if a video is marked as a decoy.
    func isDecoyVideo(_ videoDef: VideoDef) -> Bool {
        return FileManager.default.fileExists(atPath: getDecoyVideoFile(videoDef).path)
    }

    /// Adds a video as a decoy: decrypts it with the current key and re-encrypts
    /// the plaintext with the poison-pill key into the decoy directory, so it
    /// remains playable after the poison pill destroys the real key.
    func addDecoyVideoWithKey(_ videoDef: VideoDef, keyData: Data) async -> Bool {
        guard numDecoys() < Self.maxDecoyPhotos else {
            return false
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let currentKey = SymmetricKey(data: try await encryptionScheme.getDerivedKey())
            let poisonKey = SymmetricKey(data: keyData)

            let decoyDir = getDecoyDirectory()
            if !FileManager.default.fileExists(atPath: decoyDir.path) {
                try FileManager.default.createDirectory(at: decoyDir, withIntermediateDirectories: true)
            }

            // Decrypt the original (real key) to a temporary plaintext file.
            // The video encryption service opens the output via
            // FileHandle(forWritingTo:), so the output file must exist first.
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            try await videoEncryptionService.decryptVideoForSharing(
                inputURL: videoDef.videoFile,
                outputURL: tempURL,
                encryptionKey: currentKey
            )

            // Re-encrypt with the poison-pill key into the decoy directory.
            let decoyFile = getDecoyVideoFile(videoDef)
            if FileManager.default.fileExists(atPath: decoyFile.path) {
                try FileManager.default.removeItem(at: decoyFile)
            }
            FileManager.default.createFile(atPath: decoyFile.path, contents: nil)
            try await videoEncryptionService.encryptVideoForDecoy(
                inputURL: tempURL,
                outputURL: decoyFile,
                encryptionKey: poisonKey
            )

            // Preserve a poison-pill-key copy of the thumbnail so the decoy video
            // still shows a thumbnail after the poison pill destroys the real one.
            await storeDecoyVideoThumbnail(forVideoNamed: videoDef.videoName, poisonKeyData: keyData)

            return true
        } catch {
            Logger.security.error("Failed to add decoy video: \(error)")
            return false
        }
    }

    /// Removes a video's decoy copy.
    @discardableResult
    func removeDecoyVideo(_ videoDef: VideoDef) -> Bool {
        // Also drop the decoy thumbnail copy (if any).
        removeDecoyVideoThumbnail(forVideoNamed: videoDef.videoName)

        let decoyFile = getDecoyVideoFile(videoDef)
        guard FileManager.default.fileExists(atPath: decoyFile.path) else {
            return false
        }

        do {
            try FileManager.default.removeItem(at: decoyFile)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Video Import

    /// Imports a plaintext video (e.g. from the photo library): encrypts it to
    /// SECV with the current key in the videos directory and stores a thumbnail.
    /// The caller owns `plaintextURL` and should delete it afterwards.
    func importVideo(from plaintextURL: URL) async -> Bool {
        do {
            let key = SymmetricKey(data: try await encryptionScheme.getDerivedKey())

            // Match the camera's "video_yyyyMMdd_HHmmss" naming so dateTaken()
            // parses; bump the second on collision to keep names unique/sortable.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            formatter.locale = Locale(identifier: "en_US_POSIX")

            var date = Date()
            var name = "video_\(formatter.string(from: date))"
            var dest = getVideosDirectory().appendingPathComponent(name).appendingPathExtension("secv")
            while FileManager.default.fileExists(atPath: dest.path) {
                date = date.addingTimeInterval(1)
                name = "video_\(formatter.string(from: date))"
                dest = getVideosDirectory().appendingPathComponent(name).appendingPathExtension("secv")
            }

            // The encryption service opens its output via FileHandle(forWritingTo:),
            // so the file must exist first.
            FileManager.default.createFile(atPath: dest.path, contents: nil)
            try await videoEncryptionService.encryptVideoForDecoy(
                inputURL: plaintextURL,
                outputURL: dest,
                encryptionKey: key
            )

            await generateAndStoreVideoThumbnail(forVideoNamed: name, fromPlaintextVideo: plaintextURL)
            return true
        } catch {
            Logger.storage.error("Failed to import video: \(error)")
            return false
        }
    }

    // MARK: - Video Thumbnails

    private func getVideoThumbnailFile(forVideoNamed name: String) -> URL {
        return getVideoThumbnailsDirectory().appendingPathComponent(name).appendingPathExtension("jpg")
    }

    /// Generates a thumbnail from a plaintext video file (e.g. the temporary
    /// `.mov` that exists at record time) and stores it encrypted. Call this
    /// while the plaintext file still exists; the thumbnail cannot be recreated
    /// once the video is encrypted and the plaintext is deleted.
    func generateAndStoreVideoThumbnail(forVideoNamed name: String, fromPlaintextVideo url: URL) async {
        guard let image = await Self.generateThumbnail(fromVideoAt: url) else {
            Logger.storage.error("Failed to generate video thumbnail", metadata: ["video": .string(name)])
            return
        }
        await storeVideoThumbnail(image, forVideoNamed: name)
    }

    /// Stores an already-generated thumbnail image, encrypted with the current key.
    func storeVideoThumbnail(_ image: UIImage, forVideoNamed name: String) async {
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else { return }
        do {
            let dir = getVideoThumbnailsDirectory()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let file = dir.appendingPathComponent(name).appendingPathExtension("jpg")
            try await encryptionScheme.encryptToFile(plain: jpeg, targetFile: file)
            thumbnailCache.putVideoThumbnail(name, image)
        } catch {
            Logger.storage.error("Failed to store video thumbnail: \(error)")
        }
    }

    /// Reads (and decrypts) a video's thumbnail, if one exists.
    func readVideoThumbnail(_ videoDef: VideoDef) async -> UIImage? {
        if let cached = thumbnailCache.getVideoThumbnail(videoDef.videoName) {
            return cached
        }
        let file = getVideoThumbnailFile(forVideoNamed: videoDef.videoName)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let data = try await encryptionScheme.decryptFile(file)
            guard let image = UIImage(data: data) else { return nil }
            thumbnailCache.putVideoThumbnail(videoDef.videoName, image)
            return image
        } catch {
            Logger.storage.error("Failed to read video thumbnail: \(error)")
            return nil
        }
    }

    func deleteVideoThumbnail(forVideoNamed name: String) {
        thumbnailCache.evictVideoThumbnail(name)
        try? FileManager.default.removeItem(at: getVideoThumbnailFile(forVideoNamed: name))
    }

    /// Removes all video thumbnails. Used on poison-pill activation and security
    /// reset — these thumbnails are derived from real video frames and must be
    /// destroyed along with the videos themselves.
    func deleteAllVideoThumbnails() {
        try? FileManager.default.removeItem(at: getVideoThumbnailsDirectory())
    }

    private func getDecoyVideoThumbnailFile(forVideoNamed name: String) -> URL {
        return getDecoyVideoThumbnailsDirectory().appendingPathComponent(name).appendingPathExtension("jpg")
    }

    /// Re-encrypts a video's thumbnail with the poison-pill key and stores it in
    /// the decoy video thumbnails directory, so it survives the poison pill (the
    /// real-key thumbnail is destroyed then). No-op if the video has no thumbnail.
    private func storeDecoyVideoThumbnail(forVideoNamed name: String, poisonKeyData: Data) async {
        let thumbFile = getVideoThumbnailFile(forVideoNamed: name)
        guard FileManager.default.fileExists(atPath: thumbFile.path) else { return }
        do {
            let jpeg = try await encryptionScheme.decryptFile(thumbFile)
            let dir = getDecoyVideoThumbnailsDirectory()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try await encryptionScheme.encryptToFile(
                plain: jpeg,
                keyBytes: poisonKeyData,
                targetFile: getDecoyVideoThumbnailFile(forVideoNamed: name)
            )
        } catch {
            Logger.security.error("Failed to store decoy video thumbnail: \(error)")
        }
    }

    private func removeDecoyVideoThumbnail(forVideoNamed name: String) {
        try? FileManager.default.removeItem(at: getDecoyVideoThumbnailFile(forVideoNamed: name))
    }

    func deleteAllDecoyVideoThumbnails() {
        try? FileManager.default.removeItem(at: getDecoyVideoThumbnailsDirectory())
    }

    /// Moves the poison-pill-key decoy video thumbnails into the (just-wiped)
    /// video thumbnails directory. Run after `deleteAllVideoThumbnails()` during
    /// poison-pill activation.
    private func restoreDecoyVideoThumbnails() {
        let decoyDir = getDecoyVideoThumbnailsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(at: decoyDir, includingPropertiesForKeys: nil),
              !files.isEmpty else {
            return
        }

        let videoThumbsDir = getVideoThumbnailsDirectory()
        try? FileManager.default.createDirectory(at: videoThumbsDir, withIntermediateDirectories: true)

        for file in files {
            let target = videoThumbsDir.appendingPathComponent(file.lastPathComponent)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.moveItem(at: file, to: target)
        }

        try? FileManager.default.removeItem(at: decoyDir)
    }

    private static func generateThumbnail(fromVideoAt url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        // Allow some tolerance so very short clips still yield a frame.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let result = try await generator.image(at: CMTime(seconds: 0, preferredTimescale: 600))
            return UIImage(cgImage: result.image)
        } catch {
            Logger.storage.error("AVAssetImageGenerator failed: \(error)")
            return nil
        }
    }

    // MARK: - Decoy Photo Operations

    /// Adds a photo as decoy with specific key
    func addDecoyPhotoWithKey(_ photoDef: PhotoDef, keyData: Data) async -> Bool {
        guard numDecoys() < Self.maxDecoyPhotos else {
            return false
        }
        
        do {
            let jpegData = try await decryptJpg(photoDef)
            let decoyDir = getDecoyDirectory()
            
            // Create decoy directory if needed
            if !FileManager.default.fileExists(atPath: decoyDir.path) {
                try FileManager.default.createDirectory(at: decoyDir, withIntermediateDirectories: true)
            }
            
            let decoyFile = getDecoyFile(photoDef)
            try await encryptionScheme.encryptToFile(
                plain: jpegData,
                keyBytes: keyData,
                targetFile: decoyFile
            )
            
            return true
        } catch {
            return false
        }
    }
    
    /// Removes a decoy photo
    @discardableResult
    func removeDecoyPhoto(_ photoDef: PhotoDef) -> Bool {
        let decoyFile = getDecoyFile(photoDef)
        guard FileManager.default.fileExists(atPath: decoyFile.path) else {
            return false
        }
        
        do {
            try FileManager.default.removeItem(at: decoyFile)
            return true
        } catch {
            return false
        }
    }
    
    /// Removes all decoy photos
    func removeAllDecoyPhotos() {
        let decoyFiles = getDecoyFiles()
        for file in decoyFiles {
            try? FileManager.default.removeItem(at: file)
        }
    }
    
    // MARK: - Update Operations
    
    /// Updates an existing image with new image data while preserving EXIF metadata
    func updateImage(_ photoDef: PhotoDef, newImageData: Data) async throws {
        // Load existing image to extract EXIF metadata
        let existingImageData = try await decryptJpg(photoDef)
        let existingMetadata = ImageProcessing.extractEXIFMetadata(from: existingImageData)
        
        // Process the new image with preserved EXIF metadata
        let processedData = try ImageProcessing.processImageWithEXIFMetadata(
            imageData: newImageData,
            preservedEXIFMetadata: existingMetadata,
            filename: photoDef.photoName
        )
        
        // Save the updated image
        try await encryptionScheme.encryptToFile(plain: processedData, targetFile: photoDef.photoFile)
        
        // Clear thumbnail cache to force regeneration
        thumbnailCache.clearThumbnail(photoDef.photoName)
        let thumbnailFile = getThumbnailFile(photoDef)
        try? FileManager.default.removeItem(at: thumbnailFile)
    }
    
    // MARK: - Helper Methods

    struct PhotoMetaData {
        let resolution: Size
        let dateTaken: Date
        let location: GpsCoordinates?
        let orientation: TiffOrientation?
    }

    // MARK: - Main API

    @MainActor
    func getPhotoMetaData(_ photoDef: PhotoDef) async throws -> PhotoMetaData {
        let dateTaken: Date = photoDef.dateTaken() ?? Date(timeIntervalSince1970: 0)
        
        var orientation: TiffOrientation? = nil
        var coords: GpsCoordinates? = nil
        var size = Size(width: 0, height: 0)
        
        // Your decryptor should return the JPG bytes as Data
        let jpgBytes = try await decryptJpg(photoDef: photoDef)
        
        if let md = readImageMetadata(fromJPEGData: jpgBytes) {
            orientation = md.orientation
            coords = md.gps
            size = Size(width: md.width ?? 0, height: md.height ?? 0)
        }
        
        return PhotoMetaData(
            resolution: size,
            dateTaken: dateTaken,
            location: coords,
            orientation: orientation
        )
    }

    // MARK: - Decrypt (stub; replace with your implementation)

    func decryptJpg(photoDef: PhotoDef) async throws -> Data {
        return try await encryptionScheme.decryptFile(photoDef.photoFile)
    }

    // MARK: - ImageIO helpers

    private func readImageMetadata(fromJPEGData data: Data) -> ParsedImageMetadata? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        
        let pixelWidth = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let pixelHeight = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        
        var orientation: TiffOrientation? = nil
        if let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let ori = (tiff[kCGImagePropertyTIFFOrientation] as? NSNumber)?.intValue,
           let mapped = TiffOrientation(rawValue: ori) {
            orientation = mapped
        } else if let ori = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
                  let mapped = TiffOrientation(rawValue: ori) {
            // Some writers put orientation at the top level
            orientation = mapped
        }
        
        var gpsCoords: GpsCoordinates? = nil
        if let gps = props?[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude] as? NSNumber,
               let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String,
               let lon = gps[kCGImagePropertyGPSLongitude] as? NSNumber,
               let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                let latSign = (latRef.uppercased() == "S") ? -1.0 : 1.0
                let lonSign = (lonRef.uppercased() == "W") ? -1.0 : 1.0
                gpsCoords = GpsCoordinates(latitude: lat.doubleValue * latSign,
                                           longitude: lon.doubleValue * lonSign)
            }
        }
        
        return ParsedImageMetadata(
            width: pixelWidth,
            height: pixelHeight,
            orientation: orientation,
            gps: gpsCoords
        )
    }
}

// MARK: - Errors

enum ImageRepositoryError: Error {
    case compressionFailed
    case invalidImageData
}

// MARK: - Metadata

private struct ParsedImageMetadata {
    let width: Int?
    let height: Int?
    let orientation: TiffOrientation?
    let gps: GpsCoordinates?
}

struct Size {
    let width: Int
    let height: Int
}

enum TiffOrientation: Int {
    case up = 1, upMirrored = 2, down = 3, downMirrored = 4
    case leftMirrored = 5, right = 6, rightMirrored = 7, left = 8
}

struct GpsCoordinates {
    let latitude: Double
    let longitude: Double
}

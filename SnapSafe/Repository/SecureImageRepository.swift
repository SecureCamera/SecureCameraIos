//
//  SecureImageRepository.swift
//  SnapSafe
//
//  Created by Claude on 5/28/25.
//

import Foundation
import UIKit

protocol SecureImageRepositoryProtocol {
    // Core CRUD operations
    func savePhoto(_ imageData: Data, metadata: PhotoMetadata) async throws -> SecurePhoto
    func loadPhoto(withId id: String) async throws -> SecurePhoto
    func loadAllPhotos() async throws -> [SecurePhoto]
    func deletePhoto(withId id: String) async throws

    // Batch operations
    func loadPhotosWithPredicate(_ predicate: PhotoPredicate) async throws -> [SecurePhoto]
    func preloadAdjacentPhotos(currentId: String, adjacentCount: Int) async

    // Import/Export
    func importFromCamera(_ imageData: Data) async throws -> SecurePhoto
    func importFromLibrary(_ imageData: Data) async throws -> SecurePhoto
    func exportPhoto(_ photo: SecurePhoto, format: ExportFormat) async throws -> Data

    // Face detection integration
    func updateFaceDetectionResults(_ photoId: String, faces: [DetectedFace]) async throws -> SecurePhoto

    // Cache management
    func preloadThumbnails(for photoIds: [String]) async
    func clearCache()
}

final class SecureImageRepository: SecureImageRepositoryProtocol {
    private let fileSystemDataSource: FileSystemDataSourceProtocol
    private let encryptionDataSource: EncryptionDataSourceProtocol
    private let metadataDataSource: MetadataDataSourceProtocol
    private let cacheDataSource: CacheDataSourceProtocol

    init(
        fileSystemDataSource: FileSystemDataSourceProtocol,
        encryptionDataSource: EncryptionDataSourceProtocol,
        metadataDataSource: MetadataDataSourceProtocol,
        cacheDataSource: CacheDataSourceProtocol
    ) {
        self.fileSystemDataSource = fileSystemDataSource
        self.encryptionDataSource = encryptionDataSource
        self.metadataDataSource = metadataDataSource
        self.cacheDataSource = cacheDataSource
    }

    func savePhoto(_ imageData: Data, metadata: PhotoMetadata) async throws -> SecurePhoto {
        // 1. Encrypt the image data
        let encryptedData = try await encryptionDataSource.encryptImageData(imageData)

        // 2. Save encrypted data to file system
        let fileURL = try await fileSystemDataSource.saveImageData(encryptedData, withId: metadata.id)

        // 3. Save metadata
        try await metadataDataSource.saveMetadata(metadata)

        // 4. Create and cache thumbnail
        let image = UIImage(data: imageData)!
        let thumbnail = generateThumbnail(from: image)
        cacheDataSource.cacheThumbnail(thumbnail, forId: metadata.id)

        // 5. Create SecurePhoto object
        return SecurePhoto(
            id: metadata.id,
            encryptedData: encryptedData,
            metadata: metadata,
            cachedThumbnail: thumbnail
        )
    }

    func loadPhoto(withId id: String) async throws -> SecurePhoto {
        // 1. Load metadata
        guard let metadata = try await metadataDataSource.loadMetadata(withId: id) else {
            throw SecureImageRepositoryError.photoNotFound(id: id)
        }

        // 2. Check cache first
        if let cachedImage = cacheDataSource.getCachedImage(forId: id) {
            let thumbnail = cacheDataSource.getCachedThumbnail(forId: id) ?? generateThumbnail(from: cachedImage)
            return SecurePhoto(
                id: id,
                encryptedData: Data(), // Don't need encrypted data if we have cached image
                metadata: metadata,
                cachedImage: cachedImage,
                cachedThumbnail: thumbnail
            )
        }

        // 3. Load encrypted data from file system
        let encryptedData = try await fileSystemDataSource.loadImageData(withId: id)

        // 4. Check for cached thumbnail
        let cachedThumbnail = cacheDataSource.getCachedThumbnail(forId: id)

        return SecurePhoto(
            id: id,
            encryptedData: encryptedData,
            metadata: metadata,
            cachedThumbnail: cachedThumbnail
        )
    }

    func loadAllPhotos() async throws -> [SecurePhoto] {
        let allMetadata = try await metadataDataSource.loadAllMetadata()
        var photos: [SecurePhoto] = []

        for metadata in allMetadata {
            do {
                let photo = try await loadPhoto(withId: metadata.id)
                photos.append(photo)
            } catch {
                // Log error but continue loading other photos
                print("Error loading photo \(metadata.id): \(error)")
                continue
            }
        }

        return photos
    }

    func deletePhoto(withId id: String) async throws {
        // 1. Delete from file system
        try await fileSystemDataSource.deleteImageData(withId: id)

        // 2. Delete metadata
        try await metadataDataSource.deleteMetadata(withId: id)

        // 3. Clear from cache
        cacheDataSource.clearCacheForId(id)
    }

    func loadPhotosWithPredicate(_ predicate: PhotoPredicate) async throws -> [SecurePhoto] {
        let matchingMetadata = try await metadataDataSource.findMetadata(matching: predicate)
        var photos: [SecurePhoto] = []

        for metadata in matchingMetadata {
            do {
                let photo = try await loadPhoto(withId: metadata.id)
                photos.append(photo)
            } catch {
                print("Error loading photo \(metadata.id): \(error)")
                continue
            }
        }

        return photos
    }

    func preloadAdjacentPhotos(currentId: String, adjacentCount: Int = 2) async {
        do {
            let allMetadata = try await metadataDataSource.loadAllMetadata()
            guard let currentIndex = allMetadata.firstIndex(where: { $0.id == currentId }) else { return }

            // Determine adjacent photo IDs
            var adjacentIds: [String] = []
            for offset in 1 ... adjacentCount {
                if currentIndex - offset >= 0 {
                    adjacentIds.append(allMetadata[currentIndex - offset].id)
                }
                if currentIndex + offset < allMetadata.count {
                    adjacentIds.append(allMetadata[currentIndex + offset].id)
                }
            }

            // Preload adjacent photos in background
            Task {
                for id in adjacentIds {
                    do {
                        let photo = try await loadPhoto(withId: id)
                        if let image = try? await photo.decryptedImage(using: encryptionDataSource) {
                            cacheDataSource.cacheImage(image, forId: id)
                        }
                    } catch {
                        print("Error preloading photo \(id): \(error)")
                    }
                }
            }
        } catch {
            print("Error in preloadAdjacentPhotos: \(error)")
        }
    }

    func importFromCamera(_ imageData: Data) async throws -> SecurePhoto {
        let id = UUID().uuidString
        let metadata = PhotoMetadata(
            id: id,
            fileSize: imageData.count
        )
        return try await savePhoto(imageData, metadata: metadata)
    }

    func importFromLibrary(_ imageData: Data) async throws -> SecurePhoto {
        let id = UUID().uuidString
        let metadata = PhotoMetadata(
            id: id,
            fileSize: imageData.count
        )
        return try await savePhoto(imageData, metadata: metadata)
    }

    func exportPhoto(_ photo: SecurePhoto, format: ExportFormat) async throws -> Data {
        // 1. Get decrypted image
        let image = try await photo.decryptedImage(using: encryptionDataSource)

        // 2. Convert to requested format
        switch format {
        case let .jpeg(quality):
            guard let data = image.jpegData(compressionQuality: quality) else {
                throw SecureImageRepositoryError.exportFailed(reason: "Failed to convert to JPEG")
            }
            return data

        case .png:
            guard let data = image.pngData() else {
                throw SecureImageRepositoryError.exportFailed(reason: "Failed to convert to PNG")
            }
            return data

        case .heic:
            // HEIC export would require additional implementation
            throw SecureImageRepositoryError.exportFailed(reason: "HEIC export not yet implemented")
        }
    }

    func updateFaceDetectionResults(_ photoId: String, faces: [DetectedFace]) async throws -> SecurePhoto {
        guard var metadata = try await metadataDataSource.loadMetadata(withId: photoId) else {
            throw SecureImageRepositoryError.photoNotFound(id: photoId)
        }

        // Update metadata with new faces
        metadata = PhotoMetadata(
            id: metadata.id,
            creationDate: metadata.creationDate,
            modificationDate: Date(),
            fileSize: metadata.fileSize,
            faces: faces,
            maskMode: metadata.maskMode
        )

        try await metadataDataSource.updateMetadata(metadata)
        return try await loadPhoto(withId: photoId)
    }

    func preloadThumbnails(for photoIds: [String]) async {
        for photoId in photoIds {
            do {
                let photo = try await loadPhoto(withId: photoId)
                if let thumbnail = try? await photo.thumbnail(using: encryptionDataSource) {
                    cacheDataSource.cacheThumbnail(thumbnail, forId: photoId)
                }
            } catch {
                print("Error preloading thumbnail for \(photoId): \(error)")
            }
        }
    }

    func clearCache() {
        cacheDataSource.clearCache()
    }

    private func generateThumbnail(from image: UIImage, size: CGSize = CGSize(width: 200, height: 200)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

enum SecureImageRepositoryError: Error, LocalizedError {
    case photoNotFound(id: String)
    case exportFailed(reason: String)
    case encryptionFailed(reason: String)
    case fileSystemError(reason: String)

    var errorDescription: String? {
        switch self {
        case let .photoNotFound(id):
            "Photo not found with ID: \(id)"
        case let .exportFailed(reason):
            "Export failed: \(reason)"
        case let .encryptionFailed(reason):
            "Encryption failed: \(reason)"
        case let .fileSystemError(reason):
            "File system error: \(reason)"
        }
    }
}

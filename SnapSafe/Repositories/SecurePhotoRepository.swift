//
//  SecurePhotoRepository.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import CryptoKit
import Foundation
import UIKit

class SecurePhoto: Identifiable, Equatable {
    let id: String
    let rawPhotoData: Data // Store original photo data for binary fidelity
    let metadata: PhotoMetadata

    // Memory tracking
    var isVisible: Bool = false
    private var lastAccessTime: Date = .init()

    // Lazy-loaded image caches - generated from rawPhotoData on demand
    private var _cachedFullImage: UIImage?
    private var _cachedThumbnail: UIImage?

    // MARK: - Image Access Properties

    /// Full-size image loaded lazily from raw photo data
    var fullImage: UIImage {
        // Update last access time and mark as visible
        lastAccessTime = Date()
        isVisible = true

        // Return cached image if available
        if let cached = _cachedFullImage {
            return cached
        }

        // Generate full image from raw data
        guard let image = UIImage(data: rawPhotoData) else {
            print("Failed to create UIImage from rawPhotoData for photo \(id)")
            return UIImage(systemName: "photo") ?? UIImage()
        }

        // Cache the generated image
        _cachedFullImage = image
        MemoryManager.shared.reportFullImageLoaded()

        return image
    }

    /// Thumbnail image loaded lazily and cached
    var thumbnail: UIImage {
        // Update last access time and mark as visible
        lastAccessTime = Date()
        isVisible = true

        // Return cached thumbnail if available
        if let cached = _cachedThumbnail {
            return cached
        }

        // Generate thumbnail from raw data
        guard let fullSizeImage = UIImage(data: rawPhotoData) else {
            print("Failed to create thumbnail from rawPhotoData for photo \(id)")
            return UIImage(systemName: "photo") ?? UIImage()
        }

        // Generate thumbnail with proper aspect ratio preservation
        let maxThumbnailSize: CGFloat = 200
        let originalSize = fullSizeImage.size
        
        // Calculate scale factor to fit within max size while preserving aspect ratio
        let scale = min(maxThumbnailSize / originalSize.width, maxThumbnailSize / originalSize.height)
        let thumbnailSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
        let thumbnail = renderer.image { _ in
            fullSizeImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
        }

        // Cache the generated thumbnail
        _cachedThumbnail = thumbnail
        MemoryManager.shared.reportThumbnailLoaded()

        return thumbnail
    }

    // MARK: - Utility Methods

    /// Get the size of the raw photo data in bytes
    var dataSizeBytes: Int {
        rawPhotoData.count
    }

    /// Get a formatted string representation of the photo data size
    var formattedDataSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(dataSizeBytes), countStyle: .file)
    }

    // Mark as no longer visible in the UI
    func markAsInvisible() {
        isVisible = false
    }

    // Get the time since this photo was last accessed
    var timeSinceLastAccess: TimeInterval {
        Date().timeIntervalSince(lastAccessTime)
    }

    // MARK: - Memory Management

    /// Clear cached images to free memory
    func clearMemory(keepThumbnail: Bool = true) {
        // Clear full image cache
        if _cachedFullImage != nil {
            _cachedFullImage = nil
            MemoryManager.shared.reportFullImageUnloaded()
        }

        // Clear thumbnail cache if requested
        if !keepThumbnail, _cachedThumbnail != nil {
            _cachedThumbnail = nil
            MemoryManager.shared.reportThumbnailUnloaded()
        }
    }

    /// Force regenerate thumbnail from raw data (useful after photo edits)
    func regenerateThumbnail() {
        _cachedThumbnail = nil
        // Next access to thumbnail property will regenerate it
    }

    /// Force regenerate full image from raw data
    func regenerateFullImage() {
        _cachedFullImage = nil
        // Next access to fullImage property will regenerate it
    }

    // MARK: - Computed Properties

    var isDecoy: Bool {
        metadata.isDecoy
    }

    // MARK: - Initialization

    /// Initialize SecurePhoto with raw photo data
    /// - Parameters:
    ///   - id: Unique identifier for the photo
    ///   - rawPhotoData: Original photo data for binary fidelity
    ///   - metadata: Photo metadata including creation date, faces, etc.
    init(id: String, rawPhotoData: Data, metadata: PhotoMetadata) {
        self.id = id
        self.rawPhotoData = rawPhotoData
        self.metadata = metadata
    }

    /// Legacy initializer for backward compatibility during migration
    /// - Note: This converts UIImage back to Data, prefer using rawPhotoData directly
    convenience init(id: String, legacyImage: UIImage, metadata: PhotoMetadata) {
        let imageData = legacyImage.jpegData(compressionQuality: 0.95) ?? Data()
        self.init(id: id, rawPhotoData: imageData, metadata: metadata)
    }

    static func == (lhs: SecurePhoto, rhs: SecurePhoto) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Repository Extensions for Gallery Operations

extension SecurePhotoRepository {
    // MARK: - Decoy Management

    func updateDecoyStatus(for photoIds: Set<String>, isDecoy: Bool) -> Bool {
        // TODO: Implement decoy status update functionality
        // This will update the metadata for specified photos to mark them as decoys
        print("Updating decoy status for \(photoIds.count) photos to: \(isDecoy)")
        return true
    }

    func getDecoyPhotos() -> [SecurePhoto] {
        // TODO: Implement method to retrieve only decoy photos
        // This will filter photos where metadata.isDecoy == true
        []
    }

    func validateDecoyLimit(currentSelection: Set<String>, maxDecoys: Int) -> Bool {
        currentSelection.count <= maxDecoys
    }
}

// MARK: - Repository Class

class SecurePhotoRepository: ObservableObject {
    static let shared = SecurePhotoRepository()

    private let secureFileManager = SecureFileManager()

    private init() {}

    // MARK: - Core Repository Methods

    // TODO: Implement core repository methods for encrypted photo management
    // This will replace the current SecureFileManager usage in the view model
}

// enum SecurePhotoError: Error, LocalizedError {
//    case invalidImageData
//    case decryptionFailed
//
//    var errorDescription: String? {
//        switch self {
//        case .invalidImageData:
//            "Invalid image data"
//        case .decryptionFailed:
//            "Failed to decrypt image"
//        }
//    }
// }

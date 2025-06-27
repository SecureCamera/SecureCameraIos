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
    let encryptedData: Data
    let metadata: PhotoMetadata

    // Memory tracking
    var isVisible: Bool = false
    private var lastAccessTime: Date = .init()

    // Use lazy loading for images to reduce memory usage
    private var _thumbnail: UIImage?
    private var _fullImage: UIImage?

    // Cache for decrypted images
    var cachedImage: UIImage?
    var cachedThumbnail: UIImage?

    // Thumbnail is loaded on demand and cached
    var thumbnail: UIImage {
        // Update last access time and mark as visible
        lastAccessTime = Date()
        isVisible = true

        // Check for cached thumbnail first
        if let cachedThumbnail {
            return cachedThumbnail
        }

        if let legacyThumbnail = _thumbnail {
            return legacyThumbnail
        }

        // Fallback to placeholder
        return UIImage(systemName: "photo") ?? UIImage()
    }

    // Method to get thumbnail using decrypted data
//    func thumbnail(from decryptedData: Data) -> UIImage? {
//        // Check cache first
//        if let cached = cachedThumbnail {
//            return cached
//        }
//
//        // Generate thumbnail from decrypted data
//        guard let fullImage = UIImage(data: decryptedData) else {
//            return nil
//        }
//
//        // Generate thumbnail
//        let thumbnailSize = CGSize(width: 200, height: 200)
//        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
//        let thumbnail = renderer.image { _ in
//            fullImage.draw(in: CGRect(origin: .zero, size: thumbnailSize))
//        }
//
//        // Cache the thumbnail
//        cachedThumbnail = thumbnail
//        return thumbnail
//    }

    // Store decrypted image in cache
//    func cacheDecryptedImage(_ decryptedData: Data) -> UIImage? {
//        // Update last access time and mark as visible
//        lastAccessTime = Date()
//        isVisible = true
//
//        // Check cache first
//        if let cached = cachedImage {
//            return cached
//        }
//
//        // Create image from decrypted data
//        guard let image = UIImage(data: decryptedData) else {
//            return nil
//        }
//
//        // Cache the image
//        cachedImage = image
//
//        // Notify memory manager
//        MemoryManager.shared.reportFullImageLoaded()
//
//        return image
//    }

    // Mark as no longer visible in the UI
    func markAsInvisible() {
        isVisible = false
    }

    // Get the time since this photo was last accessed
    var timeSinceLastAccess: TimeInterval {
        Date().timeIntervalSince(lastAccessTime)
    }

    // Clear memory when no longer needed
    func clearMemory(keepThumbnail: Bool = true) {
        if cachedImage != nil {
            cachedImage = nil
            MemoryManager.shared.reportFullImageUnloaded()
        }

        if _fullImage != nil {
            _fullImage = nil
            MemoryManager.shared.reportFullImageUnloaded()
        }

        if !keepThumbnail {
            if cachedThumbnail != nil {
                cachedThumbnail = nil
                MemoryManager.shared.reportThumbnailUnloaded()
            }

            if _thumbnail != nil {
                _thumbnail = nil
                MemoryManager.shared.reportThumbnailUnloaded()
            }
        }
    }

    var isDecoy: Bool {
        metadata.isDecoy
    }

    var fullImage: UIImage {
        cachedImage ?? thumbnail
    }

    init(id: String, encryptedData: Data, metadata: PhotoMetadata, cachedImage: UIImage? = nil, cachedThumbnail: UIImage? = nil) {
        self.id = id
        self.encryptedData = encryptedData
        self.metadata = metadata
        self.cachedImage = cachedImage
        self.cachedThumbnail = cachedThumbnail
    }

    static func == (lhs: SecurePhoto, rhs: SecurePhoto) -> Bool {
        lhs.id == rhs.id
    }
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

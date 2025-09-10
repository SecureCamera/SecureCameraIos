//
//  SecurePhoto.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import UIKit
import FactoryKit

public class SecurePhoto: Identifiable, Equatable {
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    public let id = UUID()
    public let filename: String
    public var metadata: [String: Any]
    public let fileURL: URL

    // Memory tracking
    var isVisible: Bool = false
    private var lastAccessTime: Date = .init()

    // Use lazy loading for images to reduce memory usage
    private var _thumbnail: UIImage?
    private var _fullImage: UIImage?
    
    // Original orientation of the image from EXIF data
    var originalOrientation: UIImage.Orientation {
        // First check for our stored orientation in metadata
        if let orientationValue = metadata["originalOrientation"] as? Int {
            // Convert EXIF orientation (1-8) to UIImage.Orientation
            switch orientationValue {
            case 1: return .up                // Normal
            case 2: return .upMirrored        // Mirrored horizontally
            case 3: return .down              // Rotated 180°
            case 4: return .downMirrored      // Mirrored vertically
            case 5: return .leftMirrored      // Mirrored horizontally, then rotated 90° CCW
            case 6: return .right             // Rotated 90° CW
            case 7: return .rightMirrored     // Mirrored horizontally, then rotated 90° CW
            case 8: return .left              // Rotated 90° CCW
            default: return .up               // Default to up if invalid
            }
        }
        
        // Otherwise, inspect the image directly
        if let image = _fullImage {
            return image.imageOrientation
        }
        
        // Default to up if we can't determine
        return .up
    }

    // Computed property to check if this photo is marked as a decoy
    var isDecoy: Bool {
        return metadata["isDecoy"] as? Bool ?? false
    }

    // Thumbnail is loaded on demand and cached
    func thumbnail() async -> UIImage {
        // Update last access time and mark as visible (always do this when thumbnail is accessed)
        lastAccessTime = Date()
        isVisible = true

        if let cachedThumbnail = _thumbnail {
            return cachedThumbnail
        }

        // Load thumbnail if needed
        let photoDef = mapToPhotoDef(self)
        if let thumb = await self.secureImageRepository.readThumbnail(photoDef) {
            // Store the loaded thumbnail (with its original orientation)
            _thumbnail = thumb
            
            // Return the thumbnail, respecting its orientation
            // Note: We don't normalize the orientation here to preserve the original aspect ratio
            return thumb
        }

        // Fallback to placeholder
        return UIImage(systemName: "photo") ?? UIImage()
    }

    // Full image is loaded on demand
    func fullImage() async -> UIImage {
        // Update last access time and mark as visible (always do this when fullImage is accessed)
        lastAccessTime = Date()
        isVisible = true

        if let cachedFullImage = _fullImage {
            return cachedFullImage
        }

        // Load full image if needed
        let photoDef = mapToPhotoDef(self)
        
        if let img = try? await self.secureImageRepository.readImage(photoDef) {
            // Store the image with its original orientation
            _fullImage = img

            // When we load a full image, notify the memory manager
            MemoryManager.shared.reportFullImageLoaded()

            // Return the image with its original orientation preserved
            return img
        }

        // Fallback to thumbnail
        return await thumbnail()
    }

    // Mark as no longer visible in the UI
    func markAsInvisible() {
        isVisible = false
    }

    // Get the time since this photo was last accessed
    var timeSinceLastAccess: TimeInterval {
        return Date().timeIntervalSince(lastAccessTime)
    }

    // Clear memory when no longer needed
    func clearMemory(keepThumbnail: Bool = true) {
        if _fullImage != nil {
            _fullImage = nil

            // Notify memory manager when we free a full image
            MemoryManager.shared.reportFullImageUnloaded()
        }

        if !keepThumbnail && _thumbnail != nil {
            _thumbnail = nil

            // Notify memory manager when we free a thumbnail
            MemoryManager.shared.reportThumbnailUnloaded()
        }
    }

    init(filename: String, metadata: [String: Any], fileURL: URL, preloadedThumbnail: UIImage? = nil) {
        self.filename = filename
        self.metadata = metadata
        self.fileURL = fileURL
        _thumbnail = preloadedThumbnail
    }

    // Legacy initializer for compatibility
    convenience init(filename: String, thumbnail: UIImage, fullImage: UIImage, metadata: [String: Any]) {
        self.init(filename: filename, metadata: metadata, fileURL: URL(fileURLWithPath: ""))
        _thumbnail = thumbnail
        _fullImage = fullImage
    }

    // Implement Equatable
    nonisolated public static func == (lhs: SecurePhoto, rhs: SecurePhoto) -> Bool {
        // Compare by id and filename
        return lhs.id == rhs.id && lhs.filename == rhs.filename
    }
}

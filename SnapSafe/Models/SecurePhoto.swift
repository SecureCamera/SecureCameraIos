//
//  SecurePhoto.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import UIKit

class SecurePhoto: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    var metadata: [String: Any]
    let fileURL: URL

    // Memory tracking
    var isVisible: Bool = false
    private var lastAccessTime: Date = .init()

    // Use lazy loading for images to reduce memory usage
    private var _thumbnail: UIImage?
    private var _fullImage: UIImage?
    
    // Track if the photo is in landscape orientation (width > height)
    private var _isLandscape: Bool?
    
    // Computed property to check if the photo is in landscape orientation
    var isLandscape: Bool {
        // If we've already determined the orientation, return the cached value
        if let cachedOrientation = _isLandscape {
            return cachedOrientation
        }
        
        // Check if we have orientation info in metadata
        if let isLandscape = metadata["isLandscape"] as? Bool {
            _isLandscape = isLandscape
            return isLandscape
        }
        
        // Check the orientation value
        let orientation = originalOrientation.rawValue
        
        // Orientations 5-8 are 90/270 degree rotations (landscape)
        // For these, we need to swap width/height for comparison
        let isRotated = orientation >= 5 && orientation <= 8
        
        // Otherwise, load the full image and determine orientation by dimensions
        let image = fullImage
        let isLandscape: Bool
        
        if isRotated {
            // For rotated images, swap width/height for comparison
            isLandscape = image.size.height > image.size.width
        } else {
            // For normal orientation, compare directly
            isLandscape = image.size.width > image.size.height
        }
        
        // Cache the result
        _isLandscape = isLandscape
        
        return isLandscape
    }
    
    // Helper to get the correct dimensions for display based on orientation
    func frameSizeForDisplay(cellSize: CGFloat = 100) -> (width: CGFloat, height: CGFloat) {
        let orientation = originalOrientation.rawValue
        let isRotated = orientation >= 5 && orientation <= 8
        
        // For landscape photos or rotated portrait photos (which become landscape)
        if (isLandscape && !isRotated) || (!isLandscape && isRotated) {
            return (width: cellSize, height: cellSize * (thumbnail.size.height / thumbnail.size.width))
        } 
        // For portrait photos or rotated landscape photos (which become portrait)
        else {
            return (width: cellSize * (thumbnail.size.width / thumbnail.size.height), height: cellSize)
        }
    }
    
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

    // Function to mark/unmark as decoy
    func setDecoyStatus(_ isDecoy: Bool) {
        metadata["isDecoy"] = isDecoy

        // Save updated metadata back to disk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let secureFileManager = SecureFileManager()
                let metadataURL = try secureFileManager.getSecureDirectory().appendingPathComponent("\(filename).metadata")
                let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [])
                try metadataData.write(to: metadataURL)
                print("Updated decoy status for photo: \(filename)")
            } catch {
                print("Error updating decoy status: \(error.localizedDescription)")
            }
        }
    }

    // Thumbnail is loaded on demand and cached
    var thumbnail: UIImage {
        // Update last access time
        lastAccessTime = Date()

        if let cachedThumbnail = _thumbnail {
            return cachedThumbnail
        }

        // Load thumbnail if needed
        do {
            // Mark this photo as actively being used
            isVisible = true

            if let thumb = try secureFileManager.loadPhotoThumbnail(from: fileURL) {
                // Store the loaded thumbnail (with its original orientation)
                _thumbnail = thumb
                
                // Return the thumbnail, respecting its orientation
                // Note: We don't normalize the orientation here to preserve the original aspect ratio
                return thumb
            }
        } catch {
            print("Error loading thumbnail: \(error)")
        }

        // Fallback to placeholder
        return UIImage(systemName: "photo") ?? UIImage()
    }

    // Full image is loaded on demand
    var fullImage: UIImage {
        // Update last access time
        lastAccessTime = Date()

        if let cachedFullImage = _fullImage {
            return cachedFullImage
        }

        // Load full image if needed
        do {
            // Mark this photo as actively being used
            isVisible = true

            let (data, _) = try secureFileManager.loadPhoto(filename: filename)
            if let img = UIImage(data: data) {
                // Store the image with its original orientation
                _fullImage = img

                // When we load a full image, notify the memory manager
                MemoryManager.shared.reportFullImageLoaded()

                // Return the image with its original orientation preserved
                return img
            }
        } catch {
            print("Error loading full image: \(error)")
        }

        // Fallback to thumbnail
        return thumbnail
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
    static func == (lhs: SecurePhoto, rhs: SecurePhoto) -> Bool {
        // Compare by id and filename
        return lhs.id == rhs.id && lhs.filename == rhs.filename
    }

    // Shared file manager instance
    private let secureFileManager = SecureFileManager()
}

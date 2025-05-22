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
                _thumbnail = thumb
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
                _fullImage = img

                // When we load a full image, notify the memory manager
                MemoryManager.shared.reportFullImageLoaded()

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
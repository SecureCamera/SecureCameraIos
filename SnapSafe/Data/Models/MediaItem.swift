//
//  MediaItem.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation
import SwiftUI
import AVFoundation
import CryptoKit

// periphery:ignore all
/// Protocol for media items (photos and videos) in the gallery.
protocol MediaItem: Identifiable, Hashable {
    // periphery:ignore
    var id: UUID { get }
    var mediaName: String { get }
    // periphery:ignore
    var mediaFile: URL { get }
    var mediaType: MediaType { get }
    func dateTaken() -> Date?
    // periphery:ignore
    var thumbnail: UIImage? { get }
    // periphery:ignore
    var isEncrypted: Bool { get }
}

/// Media type enum.
enum MediaType: String, CaseIterable {
    case photo
    case video
}

// periphery:ignore all
/// Extension to make PhotoDef conform to MediaItem.
extension PhotoDef: MediaItem {
    var mediaName: String { return photoName }
    // periphery:ignore
    var mediaFile: URL { return photoFile }
    var mediaType: MediaType { return .photo }
    // periphery:ignore
    var isEncrypted: Bool { return true } // Photos are always encrypted in SnapSafe

    // Thumbnail generation for photos
    // periphery:ignore
    var thumbnail: UIImage? {
        // Use existing thumbnail logic from PhotoDef
        // This would typically load from thumbnail cache
        return nil // Placeholder - actual implementation would load thumbnail
    }
}

// periphery:ignore all
/// Extension to make VideoDef conform to MediaItem.
extension VideoDef: MediaItem {
    var mediaName: String { return videoName }
    // periphery:ignore
    var mediaFile: URL { return videoFile }
    var mediaType: MediaType { return .video }
    // isEncrypted is already defined in VideoDef.swift

    // Thumbnail generation for videos
    // periphery:ignore
    var thumbnail: UIImage? {
        return generateVideoThumbnail()
    }

    // periphery:ignore
    private func generateVideoThumbnail() -> UIImage? {
        guard FileManager.default.fileExists(atPath: videoFile.path) else {
            return nil
        }
        
        let asset: AVAsset
        if isEncrypted {
            // For encrypted videos, we need the encryption key
            // In a real app, this would come from the secure storage
            // For now, return a placeholder
            return UIImage(systemName: "video.fill")?.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        } else {
            // For unencrypted videos, generate thumbnail normally
            asset = AVURLAsset(url: videoFile)
        }
        
        let assetGenerator = AVAssetImageGenerator(asset: asset)
        assetGenerator.appliesPreferredTrackTransform = true
        
        do {
            let time = CMTime(seconds: 1, preferredTimescale: 60) // Get thumbnail at 1 second
            let cgImage = try assetGenerator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to generate video thumbnail: \(error)")
            return UIImage(systemName: "video.slash")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        }
    }
}

/// Gallery media item that can represent either a photo or video.
struct GalleryMediaItem: Identifiable, Hashable {
    let id = UUID()
    let mediaItem: any MediaItem
    let encryptionKey: SymmetricKey? // Only needed for encrypted videos

    // Convenience properties to access underlying media item
    var mediaName: String { mediaItem.mediaName }
    // periphery:ignore
    var mediaFile: URL { mediaItem.mediaFile }
    var mediaType: MediaType { mediaItem.mediaType }
    func dateTaken() -> Date? { mediaItem.dateTaken() }
    // periphery:ignore
    var thumbnail: UIImage? { mediaItem.thumbnail }
    // periphery:ignore
    var isEncrypted: Bool { mediaItem.isEncrypted }
    
    // For type-safe access to specific media types
    var photoDef: PhotoDef? {
        return mediaItem as? PhotoDef
    }
    
    var videoDef: VideoDef? {
        return mediaItem as? VideoDef
    }
    
    // Hashable conformance
    static func == (lhs: GalleryMediaItem, rhs: GalleryMediaItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
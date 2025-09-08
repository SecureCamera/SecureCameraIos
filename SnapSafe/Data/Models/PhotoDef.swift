//
//  PhotoDef.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import Foundation
import UIKit

public struct PhotoDef: Hashable, Identifiable {
    public let id = UUID()
    public let photoName: String
    public let photoFormat: String
    public let photoFile: URL
    
    public init(photoName: String, photoFormat: String, photoFile: URL) {
        self.photoName = photoName
        self.photoFormat = photoFormat
        self.photoFile = photoFile
    }
    
    public func dateTaken() -> Date? {
        // Extract date from filename format: "photo_yyyyMMdd_HHmmss_SS.jpg"
        let dateString = photoName.replacingOccurrences(of: "photo_", with: "")
            .replacingOccurrences(of: ".jpg", with: "")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss_SS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        return formatter.date(from: dateString)
    }
}

// MARK: - Utility Extensions

extension PhotoDef {
    /// Creates a PhotoDef from a SecurePhoto
    /// - Parameter securePhoto: The SecurePhoto to map from
    /// - Returns: A PhotoDef instance mapped from the SecurePhoto
    public static func from(_ securePhoto: SecurePhoto) -> PhotoDef {
        // Extract the file format from the filename
        let photoFormat = (securePhoto.filename as NSString).pathExtension.isEmpty 
            ? "jpg" 
            : (securePhoto.filename as NSString).pathExtension
        
        return PhotoDef(
            photoName: securePhoto.filename,
            photoFormat: photoFormat,
            photoFile: securePhoto.fileURL
        )
    }
    
    /// Creates multiple PhotoDef instances from an array of SecurePhoto instances
    /// - Parameter securePhotos: Array of SecurePhoto instances to map
    /// - Returns: Array of PhotoDef instances
    public static func from(_ securePhotos: [SecurePhoto]) -> [PhotoDef] {
        return securePhotos.map { PhotoDef.from($0) }
    }
}

// MARK: - Convenience Functions

/// Global utility function to map SecurePhoto to PhotoDef
/// - Parameter securePhoto: The SecurePhoto to map
/// - Returns: A PhotoDef instance
public func mapToPhotoDef(_ securePhoto: SecurePhoto) -> PhotoDef {
    return PhotoDef.from(securePhoto)
}

/// Global utility function to map multiple SecurePhotos to PhotoDefs
/// - Parameter securePhotos: Array of SecurePhoto instances
/// - Returns: Array of PhotoDef instances
public func mapToPhotoDefs(_ securePhotos: [SecurePhoto]) -> [PhotoDef] {
    return PhotoDef.from(securePhotos)
}

// MARK: - Reverse Mapping Extensions

extension PhotoDef {
    /// Creates a SecurePhoto from a PhotoDef
    /// - Parameter metadata: Optional metadata dictionary to include with the SecurePhoto. Defaults to empty dictionary.
    /// - Parameter preloadedThumbnail: Optional preloaded thumbnail image. Defaults to nil.
    /// - Returns: A SecurePhoto instance mapped from the PhotoDef
    public func toSecurePhoto(metadata: [String: Any] = [:], preloadedThumbnail: UIImage? = nil) -> SecurePhoto {
        return SecurePhoto(
            filename: photoName,
            metadata: metadata,
            fileURL: photoFile,
            preloadedThumbnail: preloadedThumbnail
        )
    }
    
    /// Creates multiple SecurePhoto instances from an array of PhotoDef instances
    /// - Parameter photoDefs: Array of PhotoDef instances to map
    /// - Parameter metadataProvider: Optional closure that provides metadata for each PhotoDef. Defaults to empty dictionary.
    /// - Parameter thumbnailProvider: Optional closure that provides preloaded thumbnails for each PhotoDef. Defaults to nil.
    /// - Returns: Array of SecurePhoto instances
    public static func toSecurePhotos(
        _ photoDefs: [PhotoDef],
        metadataProvider: ((PhotoDef) -> [String: Any])? = nil,
        thumbnailProvider: ((PhotoDef) -> UIImage?)? = nil
    ) -> [SecurePhoto] {
        return photoDefs.map { photoDef in
            let metadata = metadataProvider?(photoDef) ?? [:]
            let thumbnail = thumbnailProvider?(photoDef)
            return photoDef.toSecurePhoto(metadata: metadata, preloadedThumbnail: thumbnail)
        }
    }
}

/// Global utility function to map PhotoDef to SecurePhoto
/// - Parameter photoDef: The PhotoDef to map
/// - Parameter metadata: Optional metadata dictionary. Defaults to empty dictionary.
/// - Parameter preloadedThumbnail: Optional preloaded thumbnail. Defaults to nil.
/// - Returns: A SecurePhoto instance
public func mapToSecurePhoto(
    _ photoDef: PhotoDef,
    metadata: [String: Any] = [:],
    preloadedThumbnail: UIImage? = nil
) -> SecurePhoto {
    return photoDef.toSecurePhoto(metadata: metadata, preloadedThumbnail: preloadedThumbnail)
}

/// Global utility function to map multiple PhotoDefs to SecurePhotos
/// - Parameter photoDefs: Array of PhotoDef instances
/// - Parameter metadataProvider: Optional closure that provides metadata for each PhotoDef
/// - Parameter thumbnailProvider: Optional closure that provides preloaded thumbnails for each PhotoDef
/// - Returns: Array of SecurePhoto instances
public func mapToSecurePhotos(
    _ photoDefs: [PhotoDef],
    metadataProvider: ((PhotoDef) -> [String: Any])? = nil,
    thumbnailProvider: ((PhotoDef) -> UIImage?)? = nil
) -> [SecurePhoto] {
    return PhotoDef.toSecurePhotos(photoDefs, metadataProvider: metadataProvider, thumbnailProvider: thumbnailProvider)
}

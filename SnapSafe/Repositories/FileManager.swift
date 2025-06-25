//
//  FileManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/3/25.
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

class SecureFileManager {
    private let fileManager = FileManager.default

    // Directory isn't backed up. Local only.
    // mechanism: set the "do not backup" attribute
    func getSecureDirectory() throws -> URL {
        guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "com.securecamera", code: -1, userInfo: nil)
        }

        let secureDirectory = documentsDirectory.appendingPathComponent("SecurePhotos", isDirectory: true)

        if !fileManager.fileExists(atPath: secureDirectory.path) {
            try fileManager.createDirectory(at: secureDirectory, withIntermediateDirectories: true, attributes: nil)

            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var secureDirectoryWithAttributes = secureDirectory
            try secureDirectoryWithAttributes.setResourceValues(resourceValues)
        }

        return secureDirectory
    }

    // Save photo with UTC timestamp filename for better chronological sorting
    func savePhoto(_ photoData: Data, withMetadata metadata: [String: Any] = [:], isEdited: Bool = false, originalFilename: String? = nil) throws -> String {
        let secureDirectory = try getSecureDirectory()

        // Generate UTC timestamp filename with microsecond precision + UUID suffix for uniqueness
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let utcTimestamp = dateFormatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")

        // Add short UUID suffix to guarantee uniqueness for rapid saves
        let uuidSuffix = UUID().uuidString.prefix(8)
        let filename = "\(utcTimestamp)_\(uuidSuffix)"
        let fileURL = secureDirectory.appendingPathComponent("\(filename).photo")

        // Save photo
        try photoData.write(to: fileURL)

        // Filter metadata to only include JSON-serializable types
        var serializedMetadata = cleanMetadataForSerialization(metadata)

        // Add creation date to metadata for sorting
        let now = Date()
        serializedMetadata["creationDate"] = now.timeIntervalSince1970

        // Mark as edited if specified
        if isEdited {
            serializedMetadata["isEdited"] = true

            // Link to original photo if provided
            if let originalFilename {
                serializedMetadata["originalFilename"] = originalFilename
            }
        }

        // Add location data if enabled and available
        if let locationMetadata = LocationManager.shared.getCurrentLocationMetadata() {
            for (key, value) in locationMetadata {
                serializedMetadata[key] = value
            }
        }

        // Save metadata separately
        let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")
        let metadataData = try JSONSerialization.data(withJSONObject: serializedMetadata, options: [])
        try metadataData.write(to: metadataURL)

        return filename
    }

    // Creates a temporary file for sharing with a UUID filename
    func preparePhotoForSharing(imageData: Data) throws -> URL {
        // Get temporary directory
        let tempDirectory = FileManager.default.temporaryDirectory

        // Create UUID filename for sharing
        let uuid = UUID().uuidString
        let tempFileURL = tempDirectory.appendingPathComponent("\(uuid).jpg")

        // Write the data to the temporary file
        try imageData.write(to: tempFileURL)

        return tempFileURL
    }

    // Process metadata to make it JSON serializable
    private func cleanMetadataForSerialization(_ metadata: [String: Any]) -> [String: Any] {
        var cleanedMetadata: [String: Any] = [:]

        for (key, value) in metadata {
            if let valueDict = value as? [String: Any] {
                // Recursively clean nested dictionaries
                let cleanedValue = cleanMetadataForSerialization(valueDict)
                if !cleanedValue.isEmpty {
                    cleanedMetadata[key] = cleanedValue
                }
            } else if let valueArray = value as? [Any] {
                // Handle arrays by filtering each element
                var cleanedArray: [Any] = []
                for item in valueArray {
                    if JSONSerialization.isValidJSONObject([item]) ||
                        item is String || item is Int || item is Double || item is Bool || item is NSNull
                    {
                        cleanedArray.append(item)
                    } else if let itemDict = item as? [String: Any] {
                        let cleanedItem = cleanMetadataForSerialization(itemDict)
                        if !cleanedItem.isEmpty {
                            cleanedArray.append(cleanedItem)
                        }
                    }
                }
                if !cleanedArray.isEmpty {
                    cleanedMetadata[key] = cleanedArray
                }
            } else if value is String || value is Int || value is Double || value is Bool || value is NSNull {
                // Basic JSON-compatible types
                cleanedMetadata[key] = value
            }
            // Skip any other types (like NSData, NSDate, etc.) that aren't JSON serializable
        }

        return cleanedMetadata
    }

    // Load only photo filenames and metadata (not the actual image data)
    func loadAllPhotoMetadata() throws -> [(filename: String, metadata: [String: Any], fileURL: URL)] {
        let secureDirectory = try getSecureDirectory()
        let contents = try fileManager.contentsOfDirectory(at: secureDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)

        var photos: [(filename: String, metadata: [String: Any], fileURL: URL)] = []

        for fileURL in contents {
            if fileURL.pathExtension == "photo" {
                let filename = fileURL.deletingPathExtension().lastPathComponent

                // Try to load metadata if it exists
                let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")
                var metadata: [String: Any] = [:]

                if fileManager.fileExists(atPath: metadataURL.path) {
                    if let metadataData = try? Data(contentsOf: metadataURL) {
                        if let loadedMetadata = try? JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any] {
                            metadata = loadedMetadata
                        }
                    }
                }

                photos.append((filename: filename, metadata: metadata, fileURL: fileURL))
            }
        }

        return photos
    }

    // Load thumbnail version of a photo to reduce memory usage
    func loadPhotoThumbnail(from fileURL: URL, maxSize: CGFloat = 200) throws -> UIImage? {
        // Use image source to load a thumbnail instead of full-sized image
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        if let thumbnailCGImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) {
            return UIImage(cgImage: thumbnailCGImage)
        }

        return nil
    }

//    func loadAllPhotos() throws -> [(filename: String, data: Data, metadata: [String: Any])] {
//        let secureDirectory = try getSecureDirectory()
//        let contents = try fileManager.contentsOfDirectory(at: secureDirectory, includingPropertiesForKeys: nil)
//
//        var photos: [(filename: String, data: Data, metadata: [String: Any])] = []
//
//        for fileURL in contents {
//            if fileURL.pathExtension == "photo" {
//                let filename = fileURL.deletingPathExtension().lastPathComponent
//
//                // Load photo data
//                let photoData = try Data(contentsOf: fileURL)
//
//                // Try to load metadata if it exists
//                let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")
//                var metadata: [String: Any] = [:]
//
//                if fileManager.fileExists(atPath: metadataURL.path) {
//                    let metadataData = try Data(contentsOf: metadataURL)
//                    if let loadedMetadata = try JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any] {
//                        metadata = loadedMetadata
//                    }
//                }
//
//                photos.append((filename: filename, data: photoData, metadata: metadata))
//            }
//        }
//
//        return photos
//    }

    // Load specific photo by filename
    func loadPhoto(filename: String) throws -> (data: Data, metadata: [String: Any]) {
        let secureDirectory = try getSecureDirectory()
        let fileURL = secureDirectory.appendingPathComponent("\(filename).photo")
        let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")

        // Load photo
        let photoData = try Data(contentsOf: fileURL)

        // Load metadata if it exists
        var metadata: [String: Any] = [:]
        if fileManager.fileExists(atPath: metadataURL.path) {
            let metadataData = try Data(contentsOf: metadataURL)
            if let loadedMetadata = try JSONSerialization.jsonObject(with: metadataData, options: []) as? [String: Any] {
                metadata = loadedMetadata
            }
        }

        return (photoData, metadata)
    }

    // Delete a specific photo by filename
    func deletePhoto(filename: String) throws {
        let secureDirectory = try getSecureDirectory()
        let photoURL = secureDirectory.appendingPathComponent("\(filename).photo")
        let metadataURL = secureDirectory.appendingPathComponent("\(filename).metadata")

        // Delete the photo file
        if fileManager.fileExists(atPath: photoURL.path) {
            try fileManager.removeItem(at: photoURL)
        }

        // Delete the metadata file if it exists
        if fileManager.fileExists(atPath: metadataURL.path) {
            try fileManager.removeItem(at: metadataURL)
        }
    }

    func deleteAllPhotos() throws {
        let secureDirectory = try getSecureDirectory()
        let contents = try fileManager.contentsOfDirectory(at: secureDirectory, includingPropertiesForKeys: nil)

        for fileURL in contents {
            try fileManager.removeItem(at: fileURL)
        }
    }
}

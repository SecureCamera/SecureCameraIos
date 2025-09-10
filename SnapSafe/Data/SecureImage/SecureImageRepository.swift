//
//  SecureImageRepository.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import Foundation
import UIKit
import CoreLocation
import UniformTypeIdentifiers
import ImageIO

@MainActor
public class SecureImageRepository {
    
    // MARK: - Constants
    
    static let photosDir = "photos"
    static let decoysDir = "decoys"
    static let thumbnailsDir = ".thumbnails"
    static let maxDecoyPhotos = 10
    
    // MARK: - Dependencies
    
    let thumbnailCache: ThumbnailCache
    private let encryptionScheme: EncryptionScheme
    
    // MARK: - Initialization
    
    init(thumbnailCache: ThumbnailCache, encryptionScheme: EncryptionScheme) {
        self.thumbnailCache = thumbnailCache
        self.encryptionScheme = encryptionScheme
    }
    
    // MARK: - Directory Management
    
    func getGalleryDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(Self.photosDir)
    }
    
    func getDecoyDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(Self.decoysDir)
    }
    
    private func getThumbnailsDirectory() -> URL {
        let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let thumbnailsDir = cachesPath.appendingPathComponent(Self.thumbnailsDir)
        
        if !FileManager.default.fileExists(atPath: thumbnailsDir.path) {
            try? FileManager.default.createDirectory(at: thumbnailsDir, withIntermediateDirectories: true)
        }
        
        return thumbnailsDir
    }
    
    // MARK: - Security Operations
    
    func evictKey() {
        encryptionScheme.evictKey()
    }
    
    /// Resets all security-related data when a security failure occurs.
    /// Deletes all images and thumbnails and evicts all in-memory data.
    func securityFailureReset() {
        deleteAllImages()
        clearAllThumbnails()
        evictKey()
    }
    
    /// Deletes all images that haven't been flagged as benign
    func activatePoisonPill() {
        deleteNonDecoyImages()
        clearAllThumbnails()
        evictKey()
    }
    
    private func clearAllThumbnails() {
        let thumbnailsDir = getThumbnailsDirectory()
        try? FileManager.default.removeItem(at: thumbnailsDir)
        thumbnailCache.clear()
    }
    
    // MARK: - Image Operations
    
    /// Encrypts and saves image data to a file
    private func encryptToFile(_ data: Data, targetFile: URL) async throws {
        try await encryptionScheme.encryptToFile(plain: data, targetFile: targetFile)
    }
    
    /// Decrypts a file and returns the data
    private func decryptFile(_ encryptedFile: URL) async throws -> Data {
        return try await encryptionScheme.decryptFile(encryptedFile)
    }
    
    /// Compresses a UIImage to JPEG format with specified quality
    private func compressImageToJpeg(_ image: UIImage, quality: CGFloat) -> Data? {
        return image.jpegData(compressionQuality: quality)
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
    
    /// Applies metadata to an image
    private func applyImageMetadata(
        _ imageData: Data,
        location: CLLocation?,
        applyRotation: Bool,
        rotationDegrees: Int
    ) -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return imageData
        }
        
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return imageData
        }
        
        var properties: [String: Any] = [:]
        
        // Add current timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        properties[kCGImagePropertyExifDateTimeOriginal as String] = formatter.string(from: Date())
        
        // Add orientation
        if !applyRotation {
            let orientation = cgImageOrientation(from: rotationDegrees)
            properties[kCGImagePropertyOrientation as String] = orientation.rawValue
        }
        
        // Add GPS location if available
        if let location = location {
            let gpsInfo: [String: Any] = [
                kCGImagePropertyGPSLatitude as String: abs(location.coordinate.latitude),
                kCGImagePropertyGPSLatitudeRef as String: location.coordinate.latitude >= 0 ? "N" : "S",
                kCGImagePropertyGPSLongitude as String: abs(location.coordinate.longitude),
                kCGImagePropertyGPSLongitudeRef as String: location.coordinate.longitude >= 0 ? "E" : "W"
            ]
            properties[kCGImagePropertyGPSDictionary as String] = gpsInfo
        }
        
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        
        return mutableData as Data
    }
    
    /// Converts rotation degrees to CGImagePropertyOrientation
    private func cgImageOrientation(from degrees: Int) -> CGImagePropertyOrientation {
        switch degrees {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
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
            processedImage = rotateImage(image.sensorBitmap, degrees: image.rotationDegrees)
        }
        
        // Compress to JPEG
        guard let jpegData = compressImageToJpeg(processedImage, quality: quality) else {
            throw ImageRepositoryError.compressionFailed
        }
        
        // Apply metadata
        let updatedData = applyImageMetadata(jpegData, location: location, applyRotation: applyRotation, rotationDegrees: image.rotationDegrees)
        
        // Encrypt and save
        try await encryptAndSaveImage(updatedData, tempFile: tempFile, targetFile: photoFile)
        
        return PhotoDef(photoName: filename, photoFormat: "jpg", photoFile: photoFile)
    }
    
    /// Rotates a UIImage by the specified degrees
    private func rotateImage(_ image: UIImage, degrees: Int) -> UIImage {
        let radians = CGFloat(degrees) * .pi / 180
        
        var newSize = CGRect(origin: CGPoint.zero, size: image.size).applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        let context = UIGraphicsGetCurrentContext()!
        
        context.translateBy(x: newSize.width/2, y: newSize.height/2)
        context.rotate(by: radians)
        
        image.draw(in: CGRect(x: -image.size.width/2, y: -image.size.height/2, width: image.size.width, height: image.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
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
                print("Failed to decrypt thumbnail: \(error)")
                return nil
            }
        } else if FileManager.default.fileExists(atPath: photo.photoFile.path) {
            // Create thumbnail from full image
            do {
                let data = try await decryptFile(photo.photoFile)
                guard let fullImage = UIImage(data: data) else { return nil }
                
                // Create smaller thumbnail
                let thumbnailSize = CGSize(width: fullImage.size.width / 4, height: fullImage.size.height / 4)
                thumbnailImage = resizeImage(fullImage, to: thumbnailSize)
                
                // Cache thumbnail to file
                if let thumbnailImage = thumbnailImage,
                   let thumbnailData = thumbnailImage.jpegData(compressionQuality: 0.75) {
                    try await encryptToFile(thumbnailData, targetFile: thumbFile)
                }
            } catch {
                print("Failed to create thumbnail: \(error)")
                return nil
            }
        }
        
        // Cache in memory
        if let thumbnailImage = thumbnailImage {
            thumbnailCache.putThumbnail(photo, thumbnailImage)
        }
        
        return thumbnailImage
    }
    
    /// Resizes an image to the specified size
    private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage ?? image
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
            print("Failed to get photos: \(error)")
            return []
        }
    }
    
    /// Gets a photo by name
    func getPhotoByName(_ photoName: String) -> PhotoDef? {
        let dir = getGalleryDirectory()
        let photoFile = dir.appendingPathComponent(photoName)
        
        guard FileManager.default.fileExists(atPath: photoFile.path) else {
            return nil
        }
        
        let format = photoFile.pathExtension.isEmpty ? "jpg" : photoFile.pathExtension
        return PhotoDef(photoName: photoName, photoFormat: format, photoFile: photoFile)
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
    
    /// Gets the number of decoy photos
    func numDecoys() -> Int {
        return getDecoyFiles().count
    }
    
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
        let existingMetadata = extractEXIFMetadata(from: existingImageData)
        
        // Process the new image with preserved EXIF metadata
        let processedData = try processImageWithEXIFMetadata(
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
    
    /// Creates a copy of an image with optional modifications
    func saveImageCopy(_ photoDef: PhotoDef, modifiedImageData: Data? = nil) async throws -> PhotoDef {
        let galleryDir = getGalleryDirectory()
        let copyName = Self.generateCopyName(in: galleryDir, originalName: photoDef.photoName)
        let copyPhotoDef = PhotoDef(photoName: copyName, photoFormat: photoDef.photoFormat, photoFile: galleryDir.appendingPathComponent(copyName))
        
        let imageDataToSave: Data
        if let modifiedData = modifiedImageData {
            imageDataToSave = modifiedData
        } else {
            // Use original image data
            imageDataToSave = try await decryptJpg(photoDef)
        }
        
        // Extract EXIF metadata from source image to preserve it
        let sourceImageData = try await decryptJpg(photoDef)
        let sourceEXIFMetadata = extractEXIFMetadata(from: sourceImageData)
        
        // Process with preserved EXIF metadata
        let processedData = try processImageWithEXIFMetadata(
            imageData: imageDataToSave,
            preservedEXIFMetadata: sourceEXIFMetadata,
            filename: copyPhotoDef.photoName
        )
        
        // Save the copy
        try await encryptionScheme.encryptToFile(plain: processedData, targetFile: copyPhotoDef.photoFile)
        
        return copyPhotoDef
    }
    
    // MARK: - Private Helper Methods
    
    /// Extracts EXIF metadata from image data
    private func extractEXIFMetadata(from imageData: Data) -> [String: Any] {
        var exifMetadata: [String: Any] = [:]
        
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return exifMetadata
        }
        
        // Preserve orientation
        if let orientation = imageProperties[kCGImagePropertyOrientation as String] as? Int {
            exifMetadata[kCGImagePropertyOrientation as String] = orientation
        }
        
        // Preserve EXIF data
        if let exifDict = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyExifDictionary as String] = exifDict
        }
        
        // Preserve TIFF data
        if let tiffDict = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
        }
        
        // Preserve GPS data
        if let gpsDict = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyGPSDictionary as String] = gpsDict
        }
        
        return exifMetadata
    }
    
    /// Processes image data while preserving EXIF metadata
    private func processImageWithEXIFMetadata(
        imageData: Data,
        preservedEXIFMetadata: [String: Any],
        filename: String
    ) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw ImageRepositoryError.invalidImageData
        }
        
        // Convert to JPEG with quality
        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            throw ImageRepositoryError.compressionFailed
        }
        
        // If no EXIF metadata to preserve, return the processed image
        if preservedEXIFMetadata.isEmpty {
            return jpegData
        }
        
        // Create image destination to write JPEG with preserved metadata
        let mutableData = NSMutableData(data: jpegData)
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, type, 1, nil) else {
            return jpegData
        }
        
        // Create image source from processed JPEG
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return jpegData
        }
        
        // Add the image with preserved EXIF metadata
        CGImageDestinationAddImage(destination, cgImage, preservedEXIFMetadata as CFDictionary)
        
        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        }
        
        // Fallback to original processed image if metadata preservation fails
        return jpegData
    }
    
    // MARK: - Helper Methods
    
    static func generateCopyName(in directory: URL, originalName: String) -> String {
        let nameWithoutExtension = (originalName as NSString).deletingPathExtension
        let pathExtension = (originalName as NSString).pathExtension
        let ext = pathExtension.isEmpty ? "jpg" : pathExtension
        
        var candidate = "\(nameWithoutExtension)_cp.\(ext)"
        var counter = 1
        
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(nameWithoutExtension)_cp\(counter).\(ext)"
            counter += 1
        }
        
        return candidate
    }


    struct PhotoMetaData {
        let name: String
        let resolution: Size
        let dateTaken: Date
        let location: GpsCoordinates?
        let orientation: TiffOrientation?
    }

    // MARK: - Main API

    @MainActor
    func getPhotoMetaData(_ photoDef: PhotoDef) async throws -> PhotoMetaData {
        let name = photoDef.photoName
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
            name: name,
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
    case encryptionFailed
    case decryptionFailed
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

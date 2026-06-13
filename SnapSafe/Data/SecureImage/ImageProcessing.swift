//
//  ImageProcessing.swift
//  SnapSafe
//
//  Pure image/EXIF utilities extracted from SecureImageRepository. No file I/O,
//  no encryption, no shared state — a stateless namespace so callers (and the
//  off-main repository actor in a later phase) can run CPU-bound image work
//  without touching the data or UI layers.
//
//  NOTE: rotate/resize use the UIGraphics image-context API exactly as the
//  original code did. These run on the caller's context today (the repository
//  is still @MainActor). When the repository becomes an off-main actor in PR3,
//  re-verify thread safety or migrate these two to UIGraphicsImageRenderer.
//

import CoreLocation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum ImageProcessing {

    /// Compresses a UIImage to JPEG data with the given quality.
    static func compressImageToJpeg(_ image: UIImage, quality: CGFloat) -> Data? {
        image.jpegData(compressionQuality: quality)
    }

    /// Rotates a UIImage by the given degrees.
    static func rotateImage(_ image: UIImage, degrees: Int) -> UIImage {
        let radians = CGFloat(degrees) * .pi / 180

        var newSize = CGRect(origin: CGPoint.zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return image
        }

        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)

        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                              width: image.size.width, height: image.size.height))

        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }

    /// Resizes a UIImage to the specified size.
    static func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage ?? image
    }

    /// Converts rotation degrees to CGImagePropertyOrientation.
    static func cgImageOrientation(from degrees: Int) -> CGImagePropertyOrientation {
        switch degrees {
        case 90: return .right
        case 180: return .down
        case 270: return .left
        default: return .up
        }
    }

    /// Writes timestamp / orientation / GPS metadata into JPEG data.
    static func applyImageMetadata(
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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        properties[kCGImagePropertyExifDateTimeOriginal as String] = formatter.string(from: Date())

        if !applyRotation {
            let orientation = cgImageOrientation(from: rotationDegrees)
            properties[kCGImagePropertyOrientation as String] = orientation.rawValue
        }

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

    /// Extracts orientation/EXIF/TIFF/GPS metadata dictionaries from JPEG data.
    static func extractEXIFMetadata(from imageData: Data) -> [String: Any] {
        var exifMetadata: [String: Any] = [:]

        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return exifMetadata
        }

        if let orientation = imageProperties[kCGImagePropertyOrientation as String] as? Int {
            exifMetadata[kCGImagePropertyOrientation as String] = orientation
        }
        if let exifDict = imageProperties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyExifDictionary as String] = exifDict
        }
        if let tiffDict = imageProperties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
        }
        if let gpsDict = imageProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            exifMetadata[kCGImagePropertyGPSDictionary as String] = gpsDict
        }

        return exifMetadata
    }

    /// Re-encodes image data to JPEG, preserving the supplied EXIF metadata.
    static func processImageWithEXIFMetadata(
        imageData: Data,
        preservedEXIFMetadata: [String: Any],
        filename _: String
    ) throws -> Data {
        guard let image = UIImage(data: imageData) else {
            throw ImageRepositoryError.invalidImageData
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            throw ImageRepositoryError.compressionFailed
        }

        if preservedEXIFMetadata.isEmpty {
            return jpegData
        }

        let mutableData = NSMutableData(data: jpegData)
        let type = UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, type, 1, nil) else {
            return jpegData
        }

        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return jpegData
        }

        CGImageDestinationAddImage(destination, cgImage, preservedEXIFMetadata as CFDictionary)

        if CGImageDestinationFinalize(destination) {
            return mutableData as Data
        }

        return jpegData
    }
}

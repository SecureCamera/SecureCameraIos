//
//  ImageInfoViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/9/25.
//

import SwiftUI
import FactoryKit
import CoreGraphics
import ImageIO
import Logging


@MainActor
class ImageInfoViewModel: ObservableObject {
    private let photoDef: PhotoDef
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    // Published properties for UI state
    @Published var imageMetadata: SecureImageRepository.PhotoMetaData?
    @Published var fullImage: UIImage?
    @Published var isLoading: Bool = false
    @Published var rawMetadata: [String: Any] = [:]
    
    // MARK: - Initialization
    
    init(photoDef: PhotoDef) {
        self.photoDef = photoDef
        
        // Load data immediately
        Task {
            await loadImageData()
        }
    }
    
    // MARK: - Computed Properties
    
    var filename: String {
        photoDef.photoName
    }
    
    var resolution: String {
        guard let metadata = imageMetadata else { return "Unknown" }
        return "\(metadata.resolution.width) × \(metadata.resolution.height)"
    }
    
    var fileSize: String {
        guard let image = fullImage,
              let imageData = image.jpegData(compressionQuality: 1.0) else {
            return "Unknown"
        }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(imageData.count))
    }
    
    var dateTaken: String {
        guard let metadata = imageMetadata else { return "Not available" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: metadata.dateTaken)
    }
    
    var originalDateString: String {
        // Extract from raw metadata if available
        if let exifDict = rawMetadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
           let dateTimeOriginal = exifDict[String(kCGImagePropertyExifDateTimeOriginal)] as? String {
            return dateTimeOriginal
        }
        return "Not available"
    }
    
    var orientationString: String {
        guard let metadata = imageMetadata,
              let orientation = metadata.orientation else {
            return "Normal"
        }
        
        switch orientation {
        case .up: return "Normal"
        case .down: return "Rotated 180°"
        case .right: return "Rotated 90° CW"
        case .left: return "Rotated 90° CCW"
        case .upMirrored: return "Mirrored horizontally"
        case .downMirrored: return "Mirrored vertically"
        case .leftMirrored: return "Mirrored horizontally, rotated 90° CCW"
        case .rightMirrored: return "Mirrored horizontally, rotated 90° CW"
        }
    }
    
    var locationString: String {
        guard let metadata = imageMetadata,
              let location = metadata.location else {
            return "Not available"
        }
        
        var locationParts: [String] = []
        
        // Format latitude
        let latDirection = location.latitude >= 0 ? "N" : "S"
        locationParts.append(String(format: "%.6f°%@", abs(location.latitude), latDirection))
        
        // Format longitude
        let longDirection = location.longitude >= 0 ? "E" : "W"
        locationParts.append(String(format: "%.6f°%@", abs(location.longitude), longDirection))
        
        return locationParts.joined(separator: ", ")
    }
    
    var cameraInfo: CameraInfo {
        var info = CameraInfo()
        
        if let tiffDict = rawMetadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any] {
            info.make = tiffDict[String(kCGImagePropertyTIFFMake)] as? String
            info.model = tiffDict[String(kCGImagePropertyTIFFModel)] as? String
        }
        
        if let exifDict = rawMetadata[String(kCGImagePropertyExifDictionary)] as? [String: Any] {
            info.fNumber = exifDict[String(kCGImagePropertyExifFNumber)] as? Double
            info.exposureTime = exifDict[String(kCGImagePropertyExifExposureTime)] as? Double
            info.focalLength = exifDict[String(kCGImagePropertyExifFocalLength)] as? Double
            
            if let isoArray = exifDict[String(kCGImagePropertyExifISOSpeedRatings)] as? [Int] {
                info.iso = isoArray.first
            }
        }
        
        return info
    }
    
    // MARK: - Data Loading
    
    private func loadImageData() async {
        isLoading = true
        
        do {
            // Load the structured metadata
            let metadata = try await secureImageRepository.getPhotoMetaData(photoDef)
            
            // Load the full image
            let imageData = try await secureImageRepository.readImage(photoDef)
            guard let image = UIImage(data: imageData) else { throw ImageRepositoryError.invalidImageData }

            // Load raw JPEG data to extract raw metadata
            let jpegData = try await secureImageRepository.decryptJpg(photoDef)
            let rawMeta = extractRawMetadata(from: jpegData)

            await MainActor.run {
                self.imageMetadata = metadata
                self.fullImage = image
                self.rawMetadata = rawMeta
                self.isLoading = false
            }
        } catch {
            Logger.storage.error("Error loading image data: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func extractRawMetadata(from imageData: Data) -> [String: Any] {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return [:]
        }
        
        return imageProperties
    }
}

// MARK: - Supporting Types

struct CameraInfo {
    var make: String?
    var model: String?
    var fNumber: Double?
    var exposureTime: Double?
    var iso: Int?
    var focalLength: Double?
    
    var cameraName: String {
        if let make = make, let model = model {
            return "\(make) \(model)"
        }
        return "Unknown"
    }
    
    var apertureString: String {
        guard let fNumber = fNumber else { return "Unknown" }
        return String(format: "f/%.1f", fNumber)
    }
    
    var shutterSpeedString: String {
        guard let exposureTime = exposureTime else { return "Unknown" }
        return exposureTime < 1 ? "1/\(Int(1 / exposureTime))s" : String(format: "%.1fs", exposureTime)
    }
    
    var isoString: String {
        guard let iso = iso else { return "Unknown" }
        return "\(iso)"
    }
    
    var focalLengthString: String {
        guard let focalLength = focalLength else { return "Unknown" }
        return "\(Int(focalLength))mm"
    }
    
    var hasData: Bool {
        return make != nil || model != nil || fNumber != nil || exposureTime != nil || iso != nil || focalLength != nil
    }
}

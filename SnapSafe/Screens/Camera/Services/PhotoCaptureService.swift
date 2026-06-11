//
//  PhotoCaptureService.swift
//  SnapSafe
//
//  Created by Claude on 9/24/25.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import Logging
import FactoryKit

// periphery:ignore all
@MainActor
protocol PhotoCapturing: ObservableObject {
    // periphery:ignore
    var recentImage: UIImage? { get }
    // periphery:ignore
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode, cameraPosition: AVCaptureDevice.Position, output: AVCapturePhotoOutput, preview: AVCaptureVideoPreviewLayer?, session: AVCaptureSession)
    // periphery:ignore
    func captureMockPhoto(cameraPosition: AVCaptureDevice.Position) async
    // periphery:ignore
    func saveMockPhoto(_ imageData: Data) async
}

// periphery:ignore all
@MainActor
final class PhotoCaptureService: NSObject, ObservableObject, PhotoCapturing {
    
    // MARK: - Published Properties

    @Published var recentImage: UIImage?
    @Published var isSavingPhoto: Bool = false

    // MARK: - Dependencies
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.clock)
    private var clock: Clock
    
    @Injected(\.locationRepository)
    private var locationRepository: LocationRepository
    
    // MARK: - Public Methods
    
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode, cameraPosition: AVCaptureDevice.Position, output: AVCapturePhotoOutput, preview: AVCaptureVideoPreviewLayer?, session: AVCaptureSession) {
        isSavingPhoto = true
        let photoSettings = createAdvancedPhotoSettings()
        
        // Configure flash based on camera position
        if cameraPosition == .back {
            if output.supportedFlashModes.contains(AVCaptureDevice.FlashMode(rawValue: flashMode.rawValue)!) {
                photoSettings.flashMode = flashMode
            }
        } else {
            photoSettings.flashMode = .off
        }
        
        // Set proper rotation using AVCaptureDevice.RotationCoordinator
        guard let connection = output.connection(with: .video) else {
            output.capturePhoto(with: photoSettings, delegate: self)
            return
        }
        
        guard
            let deviceInput = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })
        else {
            output.capturePhoto(with: photoSettings, delegate: self)
            return
        }
        
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: deviceInput.device,
            previewLayer: preview
        )
        
        connection.videoRotationAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        
        output.capturePhoto(with: photoSettings, delegate: self)
    }
    
    func captureMockPhoto(cameraPosition: AVCaptureDevice.Position) async {
        isSavingPhoto = true
        Logger.camera.debug("Capturing mock photo in simulator")
        
        // Create a simple colored image for testing
        let size = CGSize(width: 1080, height: 1920)
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed]
        let randomColor = colors.randomElement() ?? .systemBlue
        
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        randomColor.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        // Add some text to make it look like a photo
        let text = "Mock Photo\n\(Date().formatted())\nCamera: \(cameraPosition == .back ? "Back" : "Front")"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        
        let mockImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        // Convert to JPEG data
        guard let imageData = mockImage.jpegData(compressionQuality: 0.8) else {
            Logger.camera.error("Failed to create mock image data")
            return
        }
        
        // Update recent image
        await MainActor.run {
            self.recentImage = mockImage
        }
        
        // Save the mock photo
        await saveMockPhoto(imageData)
    }
    
    func saveMockPhoto(_ imageData: Data) async {
        let locationTaken = locationRepository.lastLocation
        let timestamp = clock.now
        let rotation = 0
        
        let mockImage = UIImage(data: imageData)
        do {
            let photo = CapturedImage(
                sensorBitmap: mockImage!,
                timestamp: timestamp,
                rotationDegrees: rotation
            )
            let newPhotoDef = try await secureImageRepository.saveImage(
                photo,
                location: locationTaken,
                applyRotation: true
            )
            
            Logger.camera.info("Mock photo saved successfully", metadata: [
                "filename": .string(newPhotoDef.photoName)
            ])
        } catch {
            Logger.camera.error("Error saving mock photo", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
        await MainActor.run {
            self.isSavingPhoto = false
        }
    }
    
    // MARK: - Private Methods
    
    private func createAdvancedPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        return settings
    }
    
    // periphery:ignore
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }

    // Save photo with metadata extraction and secure storage
    private func savePhoto(_ imageData: Data) {
        Task(priority: .userInitiated) { [weak self] in
            var metadata: [String: Any] = [:]

            if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
               let imageMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                metadata = imageMetadata
                
                // Extract and preserve orientation information
                var exifOrientation: Int = 1
                
                if let exifDict = metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
                   let orientation = exifDict[String(kCGImagePropertyOrientation)] as? Int {
                    exifOrientation = orientation
                }
                else if let tiffDict = metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any],
                        let orientation = tiffDict[String(kCGImagePropertyTIFFOrientation)] as? Int {
                    exifOrientation = orientation
                }
                
                metadata["originalOrientation"] = exifOrientation
                
                // Determine landscape orientation based on dimensions and rotation
                if let pixelWidth = metadata[String(kCGImagePropertyPixelWidth)] as? Int,
                   let pixelHeight = metadata[String(kCGImagePropertyPixelHeight)] as? Int {
                    
                    let isRotated = (exifOrientation >= 5 && exifOrientation <= 8)
                    
                    if isRotated {
                        metadata["isLandscape"] = pixelHeight > pixelWidth
                    } else {
                        metadata["isLandscape"] = pixelWidth > pixelHeight
                    }
                }
            }
            
            let timestamp = self?.clock.now
            let rotation = 0
            let photo = UIImage(data: imageData)
            
            let image = CapturedImage(
                sensorBitmap: photo!,
                timestamp: timestamp!,
                rotationDegrees: rotation
            )
            let locationTaken = self?.locationRepository.lastLocation ?? nil
            
            do {
                let photoDef = try await self?.secureImageRepository.saveImage(
                    image,
                    location: locationTaken,
                    applyRotation: true
                )
                Logger.camera.info("Photo saved successfully", metadata: [
                    "filename": .string(photoDef?.photoName ?? "unknown")
                ])
            } catch {
                Logger.camera.error("Error saving photo", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
            await MainActor.run {
                self?.isSavingPhoto = false
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension PhotoCaptureService: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Logger.camera.error("Error capturing photo", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            Logger.camera.error("Failed to get image data")
            return
        }

        savePhoto(imageData)

        if let image = UIImage(data: imageData) {
            Task { @MainActor in
                self.recentImage = image
            }
        }
    }
    
    // Handle deferred photo processing with instant preview
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        guard error == nil else {
            Logger.camera.error("Error with deferred photo", metadata: [
                "error": .string(error!.localizedDescription)
            ])
            return
        }
        
        if let previewPixelBuffer = proxy?.previewPixelBuffer {
            let ciImage = CIImage(cvPixelBuffer: previewPixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let previewImage = UIImage(cgImage: cgImage)
                
                Task { @MainActor in
                    self.recentImage = previewImage
                }
            }
        }
    }
}

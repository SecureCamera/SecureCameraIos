//
//  CamControl.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import AVFoundation
import CoreGraphics
import CoreLocation
import ImageIO
import Photos
import UIKit

class SecureCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    private var captureSession: AVCaptureSession!
    private var photoOutput: AVCapturePhotoOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!
//    private let encryptionManager = EncryptionManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    private func setupCamera() {
        captureSession = AVCaptureSession()

        guard let backCamera = AVCaptureDevice.default(for: .video) else {
            // Handle camera unavailable
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            captureSession.addInput(input)

            photoOutput = AVCapturePhotoOutput()
            captureSession.addOutput(photoOutput)
            
            // Configure photo output for maximum quality
            if #available(iOS 17.0, *) {
                // Set quality prioritization to maximum quality over speed
                photoOutput.maxPhotoQualityPrioritization = .quality
                print("📸 Set photo quality prioritization to maximum quality")
                
                // Prepare for zero shutter lag if supported
                if photoOutput.isFastCapturePrioritizationSupported {
                    print("📸 Fast capture prioritization is supported, preparing zero shutter lag pipeline")
                    
                    // Create optimized settings for zero shutter lag
                    let zslSettings = AVCapturePhotoSettings()
                    // Note: The code snippet mentioned auto-deferred processing,
                    // but AVCapturePhotoSettings doesn't have this property
                    // We'll use the standard settings optimized for quality
                    
                    // Prime the capture pipeline with these settings
                    photoOutput.setPreparedPhotoSettingsArray([zslSettings])
                }
            } else {
                // Fall back for earlier iOS versions
                photoOutput.isHighResolutionCaptureEnabled = true
            }

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            // Configure camera device for optimal quality
            try backCamera.lockForConfiguration()
            
            // Enable subject area change monitoring
            backCamera.isSubjectAreaChangeMonitoringEnabled = true
            print("📸 Enabled subject area change monitoring")
            
            // For iOS 17+, set shutter-priority exposure for sharper images
            if #available(iOS 17.0, *) {
                if backCamera.isExposureModeSupported(.continuousAutoExposure) {
                    // Use a faster shutter speed (1/500 sec) for sharper images
                    let fastShutter = CMTime(value: 1, timescale: 500) // 1/500 sec
                    // Set ISO to a reasonable value (or max if needed)
                    let iso = min(backCamera.activeFormat.maxISO, 400)
                    
                    // Only set custom exposure if we're in good lighting conditions
                    if backCamera.exposureDuration.seconds < 0.1 { // Current exposure is faster than 1/10s
                        print("📸 Setting shutter-priority exposure: 1/500s, ISO: \(iso)")
                        backCamera.setExposureModeCustom(duration: fastShutter, iso: iso) { _ in
                            // After setting custom exposure, lock it to prevent auto changes
                            try? backCamera.lockForConfiguration()
                            backCamera.exposureMode = .locked
                            backCamera.unlockForConfiguration()
                        }
                    }
                }
            }
            
            backCamera.unlockForConfiguration()
            
            // Add observer for subject area changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(subjectAreaDidChange),
                name: .AVCaptureDeviceSubjectAreaDidChange,
                object: backCamera
            )

            captureSession.startRunning()
        } catch {
            // Handle camera setup error
        }
    }
    
    // Handle subject area changes by refocusing
    @objc private func subjectAreaDidChange(notification: NSNotification) {
        guard let device = notification.object as? AVCaptureDevice else { return }
        
        // Refocus to center or last known focus point
        let focusPoint = CGPoint(x: 0.5, y: 0.5) // Default to center
        
        do {
            try device.lockForConfiguration()
            
            // Set focus point and mode if supported
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
                print("📸 Refocusing after subject area change")
            }
            
            // Set exposure point if supported
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error refocusing: \(error.localizedDescription)")
        }
    }

    func capturePhoto() {
        // Create photo settings with advanced options for iOS 17+
        let settings: AVCapturePhotoSettings
            settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            
            // Enable image stabilization if supported
//            if photoOutput.isStillImageStabilizationSupported {
//                settings.isAutoStillImageStabilizationEnabled = true
//                print("📸 Enabled still image stabilization")
//            }
            
            // Prepare for fast capture if supported
            if photoOutput.isFastCapturePrioritizationSupported {
                print("📸 Using fast capture prioritization")
                // Note: The code snippet mentioned auto-deferred processing,
                // but AVCapturePhotoSettings doesn't have this property
            }

        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            // Handle photo capture error
            print("Error capturing photo: \(error!.localizedDescription)")
            return
        }

        // Extract and process EXIF data
        if photo.fileDataRepresentation() != nil {
//            processAndSecurePhoto(data)
        }
    }
    
    // Handle deferred photo processing (iOS 17+)
    @available(iOS 17.0, *)
    func photoOutput(_: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        guard error == nil else {
            print("Error with deferred photo: \(error!.localizedDescription)")
            return
        }
        
        print("Received deferred photo proxy with preview")
        
        // For quick preview, we could display the preview pixel buffer while waiting for the full image
        // Implementation would depend on the UI framework being used
    }

    private func processAndSecurePhoto(_ photoData: Data) {
        // Extract EXIF data before encryption
        if let image = UIImage(data: photoData),
           let _ = image.cgImage,
           let metadata = extractMetadata(from: photoData)
        {
            // Process EXIF data (location, timestamps, etc.)
            let processedEXIF = processEXIFData(metadata)

            // Save the photo without encryption for now
            do {
                // In a real implementation, we would encrypt the data first
                let secureFileManager = SecureFileManager()
                try secureFileManager.savePhoto(photoData, withMetadata: processedEXIF)
            } catch {
                // Handle save error
                print("Error saving photo: \(error.localizedDescription)")
            }
        }
    }

    private func extractMetadata(from imageData: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }

        guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        return metadata
    }

    private func processEXIFData(_ metadata: [String: Any]) -> [String: Any] {
        let processedMetadata = metadata

        // Extract GPS data if available
        if metadata[String(kCGImagePropertyGPSDictionary)] is [String: Any] {
            // Process GPS data as needed
            // Store separate from image for security
        }

        // Process other EXIF data as needed

        return processedMetadata
    }
}

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

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            // Enable subject area change monitoring
            try backCamera.lockForConfiguration()
            backCamera.isSubjectAreaChangeMonitoringEnabled = true
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
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            // Handle photo capture error
            return
        }

        // Extract and process EXIF data
        if photo.fileDataRepresentation() != nil {
//            processAndSecurePhoto(data)
        }
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

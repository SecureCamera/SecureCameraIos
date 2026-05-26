//
//  CamControl.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/3/25.
//

@preconcurrency import AVFoundation
import CoreGraphics
import CoreLocation
import ImageIO
import Photos
import UIKit
import FactoryKit
import Logging

@MainActor
class SecureCameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    private var captureSession: AVCaptureSession!
    private var photoOutput: AVCapturePhotoOutput!
    private var previewLayer: AVCaptureVideoPreviewLayer!

    @Injected(\.locationRepository)
    private var locationRepository: LocationRepository
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.clock)
    private var clock: Clock

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

            // Set quality prioritization to maximum quality over speed
            photoOutput.maxPhotoQualityPrioritization = .quality
            Logger.camera.debug("Set photo quality prioritization to maximum quality")

            // Prepare for zero shutter lag
            if photoOutput.isFastCapturePrioritizationSupported {
                Logger.camera.debug("Fast capture prioritization is supported, preparing zero shutter lag pipeline")
                let zslSettings = AVCapturePhotoSettings()
                photoOutput.setPreparedPhotoSettingsArray([zslSettings])
            }

            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            // Configure camera device for optimal quality
            try backCamera.lockForConfiguration()
            
            // Enable subject area change monitoring
            backCamera.isSubjectAreaChangeMonitoringEnabled = true
            Logger.camera.debug("Enabled subject area change monitoring")
            
            if backCamera.isExposureModeSupported(.continuousAutoExposure) {
                // Use a faster shutter speed (1/500 sec) for sharper images
                let fastShutter = CMTime(value: 1, timescale: 500) // 1/500 sec
                // Set ISO to a reasonable value (or max if needed)
                let iso = min(backCamera.activeFormat.maxISO, 400)
                
                // Only set custom exposure if we're in good lighting conditions
                if backCamera.exposureDuration.seconds < 0.1 { // Current exposure is faster than 1/10s
                    Logger.camera.debug("Setting shutter-priority exposure", metadata: [
                        "shutter": .string("1/500s"),
                        "iso": .stringConvertible(iso)
                    ])
                    backCamera.setExposureModeCustom(duration: fastShutter, iso: iso) { _ in
                        // After setting custom exposure, lock it to prevent auto changes
                        try? backCamera.lockForConfiguration()
                        backCamera.exposureMode = .locked
                        backCamera.unlockForConfiguration()
                    }
                }
            }
            
            backCamera.unlockForConfiguration()
            
            // Add observer for subject area changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(subjectAreaDidChange),
                name: AVCaptureDevice.subjectAreaDidChangeNotification,
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
                Logger.camera.debug("Refocusing after subject area change")
            }
            
            // Set exposure point if supported
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Error refocusing", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }

    func capturePhoto() {
        let settings: AVCapturePhotoSettings
            settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else {
            // Handle photo capture error
            Logger.camera.error("Error capturing photo", metadata: [
                "error": .string(error!.localizedDescription)
            ])
            return
        }
    }

    nonisolated func photoOutput(_: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        guard error == nil else {
            Logger.camera.error("Error with deferred photo", metadata: [
                "error": .string(error!.localizedDescription)
            ])
            return
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

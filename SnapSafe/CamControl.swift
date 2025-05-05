//
//  CamControl.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/3/25.
//

import UIKit
import AVFoundation
import Photos
import CoreLocation

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

            captureSession.startRunning()
        } catch {
            // Handle camera setup error
        }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
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
          let cgImage = image.cgImage,
          let metadata = extractMetadata(from: photoData) {

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
        var processedMetadata = metadata

        // Extract GPS data if available
        if let gpsInfo = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            // Process GPS data as needed
            // Store separate from image for security
        }

        // Process other EXIF data as needed

        return processedMetadata
    }
}

//
//  CameraDeviceService.swift
//  SnapSafe
//
//  Created by Claude on 9/24/25.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import Logging

protocol CameraDeviceProviding: ObservableObject {
    var session: AVCaptureSession { get }
    var output: AVCapturePhotoOutput { get }
    var currentDevice: AVCaptureDevice? { get }
    var cameraPosition: AVCaptureDevice.Position { get }
    
    func setupCamera(for position: AVCaptureDevice.Position, lensType: CameraLensType) async
    func switchCamera(to position: AVCaptureDevice.Position) async
    func switchLensType(to lensType: CameraLensType)
    func getUltraWideDevice() -> AVCaptureDevice?
    func getWideAngleDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice?
}


@MainActor
final class CameraDeviceService: ObservableObject, @preconcurrency CameraDeviceProviding {
    
    // MARK: - Published Properties
    
    @Published var session = AVCaptureSession()
    @Published var output = AVCapturePhotoOutput()
    @Published private(set) var currentDevice: AVCaptureDevice?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    
    // MARK: - Private Properties
    
    private var wideAngleDevice: AVCaptureDevice?
    private var ultraWideDevice: AVCaptureDevice?
    private var isConfiguring = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize session configuration
        session.sessionPreset = .photo
        session.automaticallyConfiguresApplicationAudioSession = false
    }
    
    // MARK: - Public Methods
    
    func setupCamera(for position: AVCaptureDevice.Position, lensType: CameraLensType) async {
        session.beginConfiguration()
        
        // Clear existing inputs
        if let inputs = session.inputs as? [AVCaptureDeviceInput] {
            for input in inputs {
                session.removeInput(input)
            }
        }
        
        // Update device references
        wideAngleDevice = getWideAngleDevice(position: position)
        
        if position == .back {
            ultraWideDevice = getUltraWideDevice()
        } else {
            ultraWideDevice = nil
        }
        
        // Select appropriate device based on lens type
        var device: AVCaptureDevice?
        let shouldUseUltraWide = lensType == .ultraWide && ultraWideDevice != nil && position == .back
        
        if shouldUseUltraWide {
            device = ultraWideDevice
        } else {
            device = wideAngleDevice
        }
        
        guard let device = device else {
            Logger.camera.error("Failed to get camera device", metadata: [
                "position": .string(String(describing: position))
            ])
            session.commitConfiguration()
            return
        }
        
        currentDevice = device
        cameraPosition = position
        
        do {
            // Configure device with optimal settings
            try device.lockForConfiguration()
            
            device.videoZoomFactor = 1.0
            
            // Enable continuous auto modes
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                device.isSmoothAutoFocusEnabled = true

                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .none
                }
            }

            // Enable face-driven autofocus (prioritizes detected faces)
            device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = true
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.unlockForConfiguration()
            
            // Add device input
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Add photo output
            if session.canAddOutput(output) {
                session.addOutput(output)
                configurePhotoOutputForMaxQuality()
            }
            
            session.commitConfiguration()
            
        } catch {
            Logger.camera.error("Error setting up camera device", metadata: [
                "error": .string(error.localizedDescription)
            ])
            session.commitConfiguration()
        }
    }
    
    func switchCamera(to position: AVCaptureDevice.Position) async {
        guard !isConfiguring else { return }
        
        if position == cameraPosition && currentDevice != nil {
            return
        }
        
        isConfiguring = true
        defer { isConfiguring = false }
        
        await setupCamera(for: position, lensType: .wideAngle)
        
        if !session.isRunning {
            Task(priority: .userInitiated) {
                session.startRunning()
            }
        }
    }
    
    func switchLensType(to lensType: CameraLensType) {
        guard !isConfiguring else { return }
        guard cameraPosition == .back || lensType == .wideAngle else { return }
        
        isConfiguring = true
        
        Task(priority: .userInitiated) { [weak self] in
            defer { 
                Task { @MainActor in
                    self?.isConfiguring = false
                }
            }
            
            await self?.setupCamera(for: self?.cameraPosition ?? .back, lensType: lensType)
            
            if let session = self?.session, !session.isRunning {
                Task(priority: .userInitiated) {
                    session.startRunning()
                }
            }
        }
    }
    
    func getUltraWideDevice() -> AVCaptureDevice? {
        if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            return ultraWide
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
    
    func getWideAngleDevice(position: AVCaptureDevice.Position = .back) -> AVCaptureDevice? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
    
    // MARK: - Private Methods
    
    private func configurePhotoOutputForMaxQuality() {
        output.maxPhotoQualityPrioritization = .quality
    }
}

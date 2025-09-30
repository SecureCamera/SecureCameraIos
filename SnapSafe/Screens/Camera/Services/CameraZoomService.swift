//
//  CameraZoomService.swift
//  SnapSafe
//
//  Created by Claude on 9/24/25.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import Logging

@MainActor
protocol ZoomControlling: ObservableObject {
    var zoomFactor: CGFloat { get }
    var minZoom: CGFloat { get }
    var maxZoom: CGFloat { get }
    var currentLensType: CameraLensType { get }
    
    func updateZoomLimits(for device: AVCaptureDevice?)
    func zoom(factor: CGFloat, device: AVCaptureDevice?) async
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat?, device: AVCaptureDevice?, onLensSwitch: @escaping (CameraLensType) -> Void)
    func resetZoomLevel(device: AVCaptureDevice?)
}

@MainActor
final class CameraZoomService: ObservableObject, ZoomControlling {
    
    // MARK: - Published Properties
    
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoom: CGFloat = 0.5
    @Published var maxZoom: CGFloat = 10.0
    @Published var currentLensType: CameraLensType = .wideAngle
    
    // MARK: - Private Properties
    
    private var initialZoom: CGFloat = 1.0
    
    // MARK: - Public Methods
    
    func updateZoomLimits(for device: AVCaptureDevice?) {
        guard let device = device else { return }
        
        let minZoomValue: CGFloat = 1.0
        let maxZoomValue = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let defaultZoomValue: CGFloat = 1.0
        
        minZoom = minZoomValue
        maxZoom = maxZoomValue
        zoomFactor = defaultZoomValue
    }
    
    // Smooth zoom with lens-specific adjustments and auto mode restoration
    func zoom(factor: CGFloat, device: AVCaptureDevice?) async {
        guard let device = device else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Restore auto modes during zoom
            if device.isExposureModeSupported(.continuousAutoExposure) && device.exposureMode != .continuousAutoExposure {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) && device.whiteBalanceMode != .continuousAutoWhiteBalance {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            var newZoomFactor = factor
            
            if currentLensType == .ultraWide {
                // Map ultra-wide zoom range (0.5x user-facing to device zoom)
                newZoomFactor = max(0.5, min(newZoomFactor, maxZoom))
                let deviceZoomFactor = (newZoomFactor / 0.5)
                let limitedDeviceZoom = min(deviceZoomFactor, device.activeFormat.videoMaxZoomFactor)
                let currentZoom = device.videoZoomFactor
                let interpolationFactor: CGFloat = 0.3
                let smoothedZoom = currentZoom + (limitedDeviceZoom - currentZoom) * interpolationFactor
                
                device.videoZoomFactor = smoothedZoom
                let userFacingZoom = max(0.5, min(newZoomFactor, maxZoom))
                
                await MainActor.run {
                    self.zoomFactor = userFacingZoom
                }
            } else {
                // Wide-angle zoom with smooth interpolation
                newZoomFactor = max(1.0, min(newZoomFactor, maxZoom))
                let currentZoom = device.videoZoomFactor
                let interpolationFactor: CGFloat = 0.3
                let smoothedZoom = currentZoom + (newZoomFactor - currentZoom) * interpolationFactor
                
                device.videoZoomFactor = smoothedZoom
                
                await MainActor.run {
                    self.zoomFactor = smoothedZoom
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Error setting zoom", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    // Handle pinch gestures with automatic lens switching and smooth zoom
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat? = nil, device: AVCaptureDevice?, onLensSwitch: @escaping (CameraLensType) -> Void) {
        if initialScale != nil {
            initialZoom = zoomFactor
        }
        
        let zoomSensitivity: CGFloat = 0.5
        let zoomDelta = pow(scale, zoomSensitivity) - 1.0
        let newZoomFactor = initialZoom + (zoomDelta * (maxZoom - minZoom))
        
        // Determine lens switching thresholds
        let shouldUseUltraWide = newZoomFactor <= 0.9 && device != nil
        let shouldUseWideAngle = newZoomFactor > 0.9
        
        if shouldUseUltraWide && currentLensType != .ultraWide {
            // Prepare auto modes for smooth lens transition
            prepareAutoModesForTransition(device: device)
            currentLensType = .ultraWide
            onLensSwitch(.ultraWide)
        } else if shouldUseWideAngle && currentLensType != .wideAngle {
            prepareAutoModesForTransition(device: device)
            currentLensType = .wideAngle
            onLensSwitch(.wideAngle)
        } else {
            // Apply zoom with auto mode restoration
            restoreAutoModes(device: device)
            
            Task {
                await zoom(factor: newZoomFactor, device: device)
            }
        }
    }
    
    // Reset zoom level to 1.0 (called when app comes from background)
    func resetZoomLevel(device: AVCaptureDevice?) {
        guard let device = device else { return }
        
        Task(priority: .userInitiated) {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
                
                await MainActor.run {
                    self.zoomFactor = 1.0
                }
            } catch {
                Logger.camera.error("Error resetting zoom level", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    func updateLensType(_ lensType: CameraLensType) {
        currentLensType = lensType
    }
    
    func updateZoomForSimulator() {
        minZoom = 0.5
        maxZoom = 10.0  
        zoomFactor = 1.0
    }
    
    // MARK: - Private Methods
    
    private func prepareAutoModesForTransition(device: AVCaptureDevice?) {
        guard let device = device else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Error preparing auto modes before lens switch", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    private func restoreAutoModes(device: AVCaptureDevice?) {
        guard let device = device else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isExposureModeSupported(.continuousAutoExposure) && device.exposureMode != .continuousAutoExposure {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) && device.whiteBalanceMode != .continuousAutoWhiteBalance {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            device.unlockForConfiguration()
        } catch {
            // Ignore errors here, it's just optimization
        }
    }
}

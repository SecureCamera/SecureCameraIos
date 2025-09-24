//
//  CameraContainerViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import SwiftUI
import AVFoundation
import Combine
import Logging

@MainActor
final class CameraContainerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var cameraModel = CameraViewModel()
    @Published var currentFlashMode: AVCaptureDevice.FlashMode = .auto
    
    // MARK: - Private Properties
    
    private var isTogglingFlash = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize flash mode from camera model
        currentFlashMode = cameraModel.flashMode
    }
    
    // MARK: - Public Methods
    
    
    func capturePhoto() {
        cameraModel.capturePhoto()
    }
    
    func toggleFlashMode() {
        // Prevent rapid consecutive toggles
        guard !isTogglingFlash else { 
            Logger.camera.debug("Flash toggle ignored - already in progress")
            return 
        }
        
        isTogglingFlash = true
        
        let currentMode = currentFlashMode
        let newMode: AVCaptureDevice.FlashMode
        
        switch currentMode {
        case .auto:
            newMode = .on
        case .on:
            newMode = .off
        case .off:
            newMode = .auto
        @unknown default:
            newMode = .auto
        }
        
        Logger.camera.debug("Flash mode cycling", metadata: [
            "from": .string(String(describing: currentMode)),
            "to": .string(String(describing: newMode))
        ])
        
        // Update both the UI state and camera model immediately
        objectWillChange.send() // Force UI update
        currentFlashMode = newMode
        cameraModel.flashMode = newMode
        
        Logger.camera.debug("Flash mode updated", metadata: [
            "mode": .string(String(describing: currentFlashMode))
        ])
        
        // Re-enable toggling after a brief delay
        Task {
            try await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                self.isTogglingFlash = false
            }
        }
    }
    
    func toggleCameraPosition() {
        Task {
            let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
            await cameraModel.switchCamera(to: newPosition)

        	// Sync flash mode state after camera switch
        	currentFlashMode = cameraModel.flashMode
        }
    }
    
    func flashIcon(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .auto:
            return "bolt.badge.a"
        case .on:
            return "bolt"
        case .off:
            return "bolt.slash"
        @unknown default:
            return "bolt.badge.a"
        }
    }
}

//
//  CameraContainerViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/7/25.
//

import SwiftUI
import AVFoundation
import Combine

@MainActor
final class CameraContainerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var cameraModel = CameraModel()
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
            print("Flash toggle ignored - already in progress")
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
        
        print("Flash mode cycling: \(currentMode) -> \(newMode)")
        
        // Update both the UI state and camera model immediately
        objectWillChange.send() // Force UI update
        currentFlashMode = newMode
        cameraModel.flashMode = newMode
        
        print("Flash mode updated to: \(currentFlashMode)")
        
        // Re-enable toggling after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isTogglingFlash = false
        }
    }
    
    func toggleCameraPosition() {
        let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
        cameraModel.switchCamera(to: newPosition)
        
        // Sync flash mode state after camera switch
        currentFlashMode = cameraModel.flashMode
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
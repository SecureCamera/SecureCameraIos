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
    
    // MARK: - Initialization
    
    init() {
        // Any initialization logic for camera container
    }
    
    // MARK: - Public Methods
    
    func capturePhoto() {
        cameraModel.capturePhoto()
    }
    
    func toggleFlashMode() {
        switch cameraModel.flashMode {
        case .auto:
            cameraModel.flashMode = .on
        case .on:
            cameraModel.flashMode = .off
        case .off:
            cameraModel.flashMode = .auto
        @unknown default:
            cameraModel.flashMode = .auto
        }
    }
    
    func toggleCameraPosition() {
        let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
        cameraModel.switchCamera(to: newPosition)
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
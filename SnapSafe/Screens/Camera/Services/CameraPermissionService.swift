//
//  CameraPermissionService.swift
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
protocol CameraPermissionProviding: ObservableObject {
    var isPermissionGranted: Bool { get }
    
    func checkAndUpdatePermissions() async -> Bool
    func updatePermissionState()
}

@MainActor
final class CameraPermissionService: ObservableObject, CameraPermissionProviding {
    
    // MARK: - Published Properties
    
    @Published private(set) var isPermissionGranted: Bool = false
    
    // MARK: - Private Properties
    
    private var isCheckingPermission = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize with current permission state synchronously to prevent UI delays
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.isPermissionGranted = (currentStatus == .authorized)
        
        // Set up notification observer for when the app becomes active
        // (in case user changed permissions in Settings)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Checks and updates camera permission state
    /// Returns true if permission is granted, false otherwise
    func checkAndUpdatePermissions() async -> Bool {
        guard !isCheckingPermission else {
            return isPermissionGranted
        }
        
        isCheckingPermission = true
        defer { isCheckingPermission = false }
        
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch currentStatus {
        case .authorized:
            updatePermissionState(granted: true)
            return true
            
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            updatePermissionState(granted: granted)
            return granted
            
        case .denied, .restricted:
            updatePermissionState(granted: false)
            return false
            
        @unknown default:
            updatePermissionState(granted: false)
            return false
        }
    }
    
    /// Synchronously updates the permission state based on current authorization status
    func updatePermissionState() {
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        updatePermissionState(granted: currentStatus == .authorized)
    }
    
    // MARK: - Private Methods
    
    private func updatePermissionState(granted: Bool) {
        Task { @MainActor in
            self.isPermissionGranted = granted
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        // Refresh permission state when app becomes active
        // (user might have changed permissions in Settings)
        // Skip if we're currently checking permissions to avoid race condition
        guard !isCheckingPermission else { return }
        updatePermissionState()
    }
}
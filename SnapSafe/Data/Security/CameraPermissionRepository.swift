//
//  CameraPermissionRepository.swift
//  SnapSafe
//
//  Created by Bill Booth on 9/12/25.
//

import Foundation
import Combine
import AVFoundation
import SwiftUI

/// Manages camera permission state and provides reactive updates to the UI
/// We need this to handle transitions between camera permissions being turned on/off
@MainActor
public final class CameraPermissionRepository: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current camera permission state - reactive for SwiftUI
    @Published public private(set) var isPermissionGranted: Bool = false
    
    // MARK: - Private Properties
    
    private var isCheckingPermission = false
    
    // MARK: - Initialization
    
    public init() {
        // Initialize with current permission state synchronously to prevent UI delays
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.isPermissionGranted = (currentStatus == .authorized)
        
        // Set up notification observer for when the app becomes active
        // (in case user changed permissions in Settings)
        // NOTE: The UIApplication bit should be the only import from SwiftUI here
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
    public func checkAndUpdatePermissions() async -> Bool {
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
    public func updatePermissionState() {
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
        updatePermissionState()
    }
}

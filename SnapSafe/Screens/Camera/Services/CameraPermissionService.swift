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

// periphery:ignore all
@MainActor
protocol CameraPermissionProviding: ObservableObject {
    // periphery:ignore
    var isPermissionGranted: Bool { get }
    // periphery:ignore
    func checkAndUpdatePermissions() async -> Bool
    // periphery:ignore
    func updatePermissionState()
}

// periphery:ignore all
@MainActor
final class CameraPermissionService: ObservableObject, CameraPermissionProviding {

    // MARK: - Published Properties

    @Published private(set) var isPermissionGranted: Bool = false

    // MARK: - Private Properties

    private var isCheckingPermission = false

    // MARK: - Debug/Simulator Detection

    // periphery:ignore
    private var isRunningInSimulator: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Initialization

    init() {
        // Simulator always has camera permissions granted in DEBUG builds
        #if DEBUG && targetEnvironment(simulator)
        self.isPermissionGranted = true
        #else
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
        #endif
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Checks and updates camera permission state
    /// Returns true if permission is granted, false otherwise
    func checkAndUpdatePermissions() async -> Bool {
        #if DEBUG && targetEnvironment(simulator)
        // Simulator always has permissions in DEBUG builds
        return true
        #else
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
        #endif
    }
    
    /// Synchronously updates the permission state based on current authorization status
    func updatePermissionState() {
        #if DEBUG && targetEnvironment(simulator)
        // Simulator always has permissions in DEBUG builds
        updatePermissionState(granted: true)
        #else
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        updatePermissionState(granted: currentStatus == .authorized)
        #endif
    }
    
    // MARK: - Private Methods
    
    private func updatePermissionState(granted: Bool) {
        Task { @MainActor in
            self.isPermissionGranted = granted
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        #if DEBUG && targetEnvironment(simulator)
        // Simulator always has permissions in DEBUG builds - no need to check
        return
        #else
        // Refresh permission state when app becomes active
        // (user might have changed permissions in Settings)
        // Skip if we're currently checking permissions to avoid race condition
        guard !isCheckingPermission else { return }
        updatePermissionState()
        #endif
    }
}

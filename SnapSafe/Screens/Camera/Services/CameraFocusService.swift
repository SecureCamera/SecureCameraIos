//
//  CameraFocusService.swift
//  SnapSafe
//
//  Created by Claude on 9/24/25.
//

import Foundation
@preconcurrency import AVFoundation
import SwiftUI
import Combine
import Logging

@MainActor
protocol FocusControlling: ObservableObject {
    var focusIndicatorPoint: CGPoint? { get }
    var showingFocusIndicator: Bool { get }
    
    func setupSubjectAreaChangeMonitoring(for device: AVCaptureDevice)
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool, device: AVCaptureDevice?)
    func showFocusIndicator(on viewPoint: CGPoint)
    func startPeriodicFocusCheck(device: AVCaptureDevice?)
    func stopPeriodicFocusCheck()
}

@MainActor
final class CameraFocusService: ObservableObject, FocusControlling {
    
    // MARK: - Published Properties
    
    @Published var focusIndicatorPoint: CGPoint? = nil
    @Published var showingFocusIndicator = false
    
    // MARK: - Private Properties
    
    private var focusResetTimer: Timer?
    private var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private var focusCheckTimer: Timer?
    private weak var currentDevice: AVCaptureDevice?
    
    // MARK: - Public Methods
    
    func setupSubjectAreaChangeMonitoring(for device: AVCaptureDevice) {
        // Remove existing observer if any
        if let currentDevice = currentDevice {
            NotificationCenter.default.removeObserver(self, name: AVCaptureDevice.subjectAreaDidChangeNotification, object: currentDevice)
        }
        
        currentDevice = device
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device
        )
    }
    
    // Tap-to-focus with optional white balance locking
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool = false, device: AVCaptureDevice?) {
        guard let device = device else { return }
        lastFocusPoint = point
        focusResetTimer?.invalidate()
        
        do {
            try device.lockForConfiguration()
            // Set focus and exposure points
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
                
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }
            }
            
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            
            // Handle white balance based on lock preference
            if lockWhiteBalance && device.isWhiteBalanceModeSupported(.locked) {
                // Lock at the current white balance. Do NOT use
                // setWhiteBalanceModeLocked(with:) here: custom-gains locking is
                // unsupported on virtual devices (dual-wide/triple camera) and
                // throws NSInvalidArgumentException.
                device.whiteBalanceMode = .locked
            } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            device.unlockForConfiguration()
            
            // Schedule auto-focus reset with appropriate delay
            let resetDelay = lockWhiteBalance ? 8.0 : 3.0
            focusResetTimer = Timer.scheduledTimer(withTimeInterval: resetDelay, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.resetToAutoFocus(device: device)
                }
            }
        } catch {
            Logger.camera.error("Error adjusting camera settings", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    func showFocusIndicator(on viewPoint: CGPoint) {
        Task {
            self.focusIndicatorPoint = viewPoint
            self.showingFocusIndicator = true

            try await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) {
                self.showingFocusIndicator = false
            }
        }
    }
    
    func startPeriodicFocusCheck(device: AVCaptureDevice?) {
        stopPeriodicFocusCheck()
        currentDevice = device
        
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAndOptimizeFocus()
            }
        }
    }
    
    func stopPeriodicFocusCheck() {
        focusCheckTimer?.invalidate()
        focusCheckTimer = nil
    }
    
    // MARK: - Private Methods
    
    @objc private func subjectAreaDidChange(notification: Notification) {
        refocusCamera()
    }
    
    // Refocus camera to last focus point when subject area changes
    private func refocusCamera() {
        guard let device = currentDevice else { return }
        
        if device.focusMode != .locked {
            do {
                try device.lockForConfiguration()
                
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = lastFocusPoint
                    device.focusMode = .autoFocus
                }
                
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = lastFocusPoint
                    device.exposureMode = .autoExpose
                }
                
                device.unlockForConfiguration()
                focusResetTimer?.invalidate()
                focusResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.resetToAutoFocus(device: device)
                    }
                }
                
            } catch {
                Logger.camera.error("Error refocusing camera", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    // Ensure continuous auto-focus remains active
    private func checkAndOptimizeFocus() {
        guard let device = currentDevice else { return }
        
        if device.focusMode != .locked {
            do {
                try device.lockForConfiguration()
                
                if device.focusMode != .continuousAutoFocus && device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                
                device.unlockForConfiguration()
            } catch {
                Logger.camera.error("Error in focus check", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    // Return to continuous auto modes after manual adjustments
    private func resetToAutoFocus(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Error resetting focus", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    // MARK: - Cleanup

    nonisolated deinit {
        // These operations can be performed in a nonisolated context
        // The timers and notification center operations are thread-safe
    }
}

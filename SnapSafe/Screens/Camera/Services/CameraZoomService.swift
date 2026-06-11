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

// periphery:ignore all
@MainActor
protocol ZoomControlling: ObservableObject {
    // periphery:ignore
    var zoomFactor: CGFloat { get }
    // periphery:ignore
    var minZoom: CGFloat { get }
    // periphery:ignore
    var maxZoom: CGFloat { get }
    // periphery:ignore
    var zoomDetents: [CGFloat] { get }
    // periphery:ignore
    func updateZoomLimits(for device: AVCaptureDevice?)
    // periphery:ignore
    func zoom(factor: CGFloat, device: AVCaptureDevice?) async
    // periphery:ignore
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat?, device: AVCaptureDevice?)
    // periphery:ignore
    func resetZoomLevel(device: AVCaptureDevice?)
    // periphery:ignore
    func snapToNearestDetent(threshold: CGFloat) async
}

/// Controls zoom on a single (virtual) capture device.
///
/// The session runs one virtual device (dual-wide/triple camera) whose
/// `videoZoomFactor` spans every constituent lens, so crossing 1.0x is a
/// seamless, system-managed lens switch — no session rebuild and no manual
/// lens bookkeeping. `CameraZoomMapping` converts between the user-facing
/// display zoom (0.5x, 1x, 2x…) and the device's zoom-factor space.
// periphery:ignore all
@MainActor
final class CameraZoomService: ObservableObject, ZoomControlling {

    // MARK: - Published Properties

    /// Display zoom — what the UI shows (0.5x … 10x).
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 10.0

    // MARK: - Public Properties

    // periphery:ignore
    let zoomDetents: [CGFloat] = [0.5, 1.0, 2.0, 3.0, 5.0, 10.0]

    // MARK: - Private Properties

    private var mapping = CameraZoomMapping(switchOverFactors: [], maxDeviceZoom: 10.0)
    private var initialZoom: CGFloat = 1.0
    private weak var currentDevice: AVCaptureDevice?

    // MARK: - Public Methods

    func updateZoomLimits(for device: AVCaptureDevice?) {
        guard let device else { return }
        currentDevice = device

        mapping = CameraZoomMapping(device: device)
        minZoom = mapping.minDisplayZoom
        maxZoom = mapping.maxDisplayZoom

        // Always start at display 1.0x (the wide lens). A virtual device's
        // default `videoZoomFactor` of 1.0 is the ultra-wide lens, which maps
        // to display 0.5x — so reflecting the device default would come up
        // zoomed out. Actively position the device at display 1.0x instead.
        let initialDisplayZoom = mapping.clampedDisplayZoom(1.0)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = mapping.deviceZoom(forDisplayZoom: initialDisplayZoom)
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Error setting initial zoom", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
        zoomFactor = initialDisplayZoom
    }

    func zoom(factor: CGFloat, device: AVCaptureDevice?) async {
        guard let device else { return }

        do {
            try device.lockForConfiguration()

            // Zooming after tap-to-focus should release any locked modes.
            restoreAutoModes(on: device)

            let displayZoom = mapping.clampedDisplayZoom(factor)
            device.videoZoomFactor = mapping.deviceZoom(forDisplayZoom: displayZoom)
            device.unlockForConfiguration()

            zoomFactor = displayZoom
        } catch {
            Logger.camera.error("Error setting zoom", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }

    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat? = nil, device: AVCaptureDevice?) {
        if initialScale != nil {
            initialZoom = zoomFactor
        }

        let zoomSensitivity: CGFloat = 0.5
        let zoomDelta = pow(scale, zoomSensitivity) - 1.0
        let newZoomFactor = initialZoom + (zoomDelta * (maxZoom - minZoom))

        Task {
            await zoom(factor: newZoomFactor, device: device)
        }
    }

    /// Reset to display 1.0x (mode switches, returning from background).
    func resetZoomLevel(device: AVCaptureDevice?) {
        guard let device else { return }

        Task(priority: .userInitiated) {
            await zoom(factor: 1.0, device: device)
        }
    }

    // periphery:ignore
    func updateZoomForSimulator() {
        minZoom = 0.5
        maxZoom = 10.0
        zoomFactor = 1.0
    }

    // periphery:ignore
    func snapToNearestDetent(threshold: CGFloat) async {
        let currentZoom = zoomFactor
        var closestLevel = currentZoom
        var minDistance = CGFloat.greatestFiniteMagnitude

        for level in zoomDetents where level >= minZoom && level <= maxZoom {
            let distance = abs(currentZoom - level)
            if distance < minDistance && distance <= threshold {
                minDistance = distance
                closestLevel = level
            }
        }

        if closestLevel != currentZoom {
            await zoom(factor: closestLevel, device: currentDevice)
        }
    }

    // MARK: - Private Methods

    /// Device must already be locked for configuration.
    private func restoreAutoModes(on device: AVCaptureDevice) {
        if device.isExposureModeSupported(.continuousAutoExposure) && device.exposureMode != .continuousAutoExposure {
            device.exposureMode = .continuousAutoExposure
        }

        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) && device.whiteBalanceMode != .continuousAutoWhiteBalance {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
    }
}

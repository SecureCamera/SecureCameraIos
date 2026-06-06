//
//  CameraDeviceService.swift
//  SnapSafe
//
//  Created by Claude on 9/24/25.
//

import Foundation
@preconcurrency import AVFoundation
import SwiftUI
import Combine
import Logging

protocol CameraDeviceProviding: ObservableObject {
    var session: AVCaptureSession { get }
    var output: AVCapturePhotoOutput { get }
    var movieOutput: AVCaptureMovieFileOutput { get }
    var currentDevice: AVCaptureDevice? { get }
    var cameraPosition: AVCaptureDevice.Position { get }

    func setupCamera(for position: AVCaptureDevice.Position) async
    func switchCamera(to position: AVCaptureDevice.Position) async
    func configureForMode(_ mode: CaptureMode)
}


@MainActor
final class CameraDeviceService: ObservableObject, @preconcurrency CameraDeviceProviding {
    
    // MARK: - Published Properties

    @Published var session = AVCaptureSession()
    @Published var output = AVCapturePhotoOutput()
    @Published var movieOutput = AVCaptureMovieFileOutput()
    @Published private(set) var currentDevice: AVCaptureDevice?
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var currentCaptureMode: CaptureMode = .photo

    // MARK: - Private Properties

    private var audioInput: AVCaptureDeviceInput?
    private var isConfiguring = false

    // MARK: - Initialization

    init() {
        // Initialize session configuration
        // Use .high preset to support both photo and video capture
        session.sessionPreset = .high
        // Allow automatic audio session configuration for video recording
        session.automaticallyConfiguresApplicationAudioSession = true
    }
    
    // MARK: - Public Methods
    
    func setupCamera(for position: AVCaptureDevice.Position) async {
        session.beginConfiguration()

        // Clear existing inputs
        if let inputs = session.inputs as? [AVCaptureDeviceInput] {
            for input in inputs {
                session.removeInput(input)
            }
        }

        guard let device = camera(for: position) else {
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

            // Start at display 1.0x. On a virtual device with an ultra-wide
            // constituent, that is the wide-lens switch-over factor, not 1.0.
            device.videoZoomFactor = CameraZoomMapping(device: device).deviceZoom(forDisplayZoom: 1.0)

            // Enable continuous auto modes
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                device.isSmoothAutoFocusEnabled = true

                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .none
                }
            }

            // Enable face-driven autofocus (prioritizes detected faces)
            // Only available on rear cameras with autofocus support
            // Front cameras don't support this feature and will crash if enabled
            if position == .back && device.isFocusModeSupported(.continuousAutoFocus) {
                device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = true
            }
            
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

            // Add movie output (keep both attached for smooth mode switching)
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
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

        await setupCamera(for: position)

        if !session.isRunning {
            Task(priority: .userInitiated) {
                session.startRunning()
            }
        }
    }

    /// Picks the best camera for a position. For the back position this is the
    /// most capable virtual device: its `videoZoomFactor` spans all constituent
    /// lenses, and AVFoundation switches between them seamlessly — there is no
    /// session reconfiguration when zoom crosses a lens boundary.
    private func camera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            return AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Capture Mode Configuration

    func configureForMode(_ mode: CaptureMode) {
        guard !isConfiguring else { return }
        guard mode != currentCaptureMode else { return }

        isConfiguring = true

        // Capture references for use in background queue
        let session = self.session
        let currentAudioInput = self.audioInput

        // Run session configuration on background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            var newAudioInput: AVCaptureDeviceInput?

            session.beginConfiguration()

            switch mode {
            case .photo:
                // Remove audio input if present (not needed for photos)
                if let audioInput = currentAudioInput, session.inputs.contains(audioInput) {
                    session.removeInput(audioInput)
                }

            case .video:
                // Add audio input for video recording (if not already present)
                if currentAudioInput == nil {
                    if let audioDevice = AVCaptureDevice.default(for: .audio) {
                        do {
                            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                            if session.canAddInput(audioInput) {
                                session.addInput(audioInput)
                                newAudioInput = audioInput
                            }
                        } catch {
                            Logger.camera.error("Failed to add audio input: \(error.localizedDescription)")
                        }
                    }
                } else {
                    newAudioInput = currentAudioInput
                }
            }

            session.commitConfiguration()

            // Update state on main thread.
            // newAudioInput is AVCaptureDeviceInput? which isn't Sendable; we know
            // crossing back to MainActor here is safe because nothing else races on it.
            nonisolated(unsafe) let resolvedAudioInput = newAudioInput
            Task { @MainActor [weak self] in
                self?.audioInput = resolvedAudioInput
                self?.currentCaptureMode = mode
                self?.isConfiguring = false
                Logger.camera.info("Configured camera for mode: \(String(describing: mode))")
            }
        }
    }

    // MARK: - Audio Input Management

    private func addAudioInput() {
        guard audioInput == nil else { return }

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            Logger.camera.warning("No audio device available")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
                Logger.camera.debug("Added audio input")
            }
        } catch {
            Logger.camera.error("Failed to add audio input: \(error.localizedDescription)")
        }
    }

    private func removeAudioInput() {
        guard let audioInput = audioInput else { return }

        if session.inputs.contains(audioInput) {
            session.removeInput(audioInput)
        }
        self.audioInput = nil
        Logger.camera.debug("Removed audio input")
    }

    // MARK: - Private Methods

    private func configurePhotoOutputForMaxQuality() {
        output.maxPhotoQualityPrioritization = .quality
    }
}

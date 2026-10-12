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

// periphery:ignore all
protocol CameraDeviceProviding: ObservableObject {
    // periphery:ignore
    var session: AVCaptureSession { get }
    // periphery:ignore
    var output: AVCapturePhotoOutput { get }
    // periphery:ignore
    var movieOutput: AVCaptureMovieFileOutput { get }
    // periphery:ignore
    var currentDevice: AVCaptureDevice? { get }
    // periphery:ignore
    var cameraPosition: AVCaptureDevice.Position { get }
    // periphery:ignore
    func setupCamera(for position: AVCaptureDevice.Position) async
    // periphery:ignore
    func switchCamera(to position: AVCaptureDevice.Position) async
    // periphery:ignore
    func configureForMode(_ mode: CaptureMode)
}


// periphery:ignore all
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
    private var isConfigured = false

    /// Audio-session configuration in effect before a recording, restored on
    /// detach so playback behavior elsewhere in the app is unaffected.
    private var previousAudioConfiguration: (
        category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    )?

    // MARK: - Initialization

    init() {
        // Initialize session configuration
        // Use .high preset to support both photo and video capture
        session.sessionPreset = .high
        // We configure the app's shared AVAudioSession ourselves (see
        // attachAudioInput). Left automatic, the capture session reconfigures
        // the audio session (category, mic selection, polar pattern) inside
        // the commitConfiguration that adds/removes the mic input — and doing
        // that against the RUNNING session stalls the video pipeline, so the
        // preview flashes black at recording start and stop.
        session.automaticallyConfiguresApplicationAudioSession = false
    }
    
    // MARK: - Public Methods
    
    func setupCamera(for position: AVCaptureDevice.Position) async {
        // Idempotent: the session's inputs/outputs only need to be built once.
        // Re-running this removes the video input from a live session, so the
        // preview momentarily has no feed and the black backdrop flashes through
        // (e.g. on every return to the camera screen). Front/back changes go via
        // switchCamera; app-background restarts via restartCameraSessionIfNeeded.
        guard !isConfigured else { return }

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

            // Add photo output (first setup only; switchCamera re-runs setup
            // with the output already attached)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            configurePhotoOutputForMaxQuality(for: device)

            // Add movie output (keep both attached for smooth mode switching)
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }

            session.commitConfiguration()
            isConfigured = true

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

        // A camera switch must rebuild the session inputs for the new device, so
        // clear the idempotency guard that setupCamera honors (it's there to skip
        // a redundant rebuild on re-appear, not to block an actual switch).
        isConfigured = false
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
        guard mode != currentCaptureMode else { return }

        // Switching modes no longer reconfigures the session. The movie output
        // stays attached (added once in setupCamera) and the microphone is
        // attached only while actually recording (see attachAudioInput). This
        // keeps photo/video toggling free of session reconfiguration — which
        // otherwise briefly stalls the live preview and makes it flicker — and
        // keeps the system mic indicator off until recording begins.
        currentCaptureMode = mode
        Logger.camera.info("Configured camera for mode: \(String(describing: mode))")
    }

    // MARK: - Audio Input Management

    /// Attaches the microphone input. Adding it activates the system mic
    /// indicator, so this is called only while recording — not on entering
    /// video mode. Wrapped in begin/commitConfiguration so the change applies
    /// atomically just before recording starts.
    func attachAudioInput() {
        guard audioInput == nil else { return }

        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            Logger.camera.warning("No audio device available")
            return
        }

        // The capture session no longer auto-configures the audio session
        // (see init), so put a recording-capable category in place BEFORE
        // wiring the mic into the running capture graph — this keeps the
        // commit below from touching audio routing, which is what made the
        // preview flash black. The previous configuration is restored on
        // detach.
        let audioSession = AVAudioSession.sharedInstance()
        previousAudioConfiguration = (
            audioSession.category, audioSession.mode, audioSession.categoryOptions
        )
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker])
        } catch {
            Logger.camera.warning("Failed to configure audio session for recording: \(error.localizedDescription)")
        }

        do {
            let input = try AVCaptureDeviceInput(device: audioDevice)
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
                audioInput = input
                Logger.camera.debug("Added audio input")
            }
            session.commitConfiguration()
        } catch {
            Logger.camera.error("Failed to add audio input: \(error.localizedDescription)")
        }
    }

    /// Detaches the microphone input once recording stops, releasing the mic
    /// and clearing the system indicator.
    func detachAudioInput() {
        guard let audioInput = audioInput else { return }

        session.beginConfiguration()
        if session.inputs.contains(audioInput) {
            session.removeInput(audioInput)
        }
        session.commitConfiguration()
        self.audioInput = nil

        // Hand the audio session back to its pre-recording configuration so
        // the record-capable category doesn't re-engage the mic route when
        // something else (e.g. the gallery player) activates audio later.
        if let previous = previousAudioConfiguration {
            previousAudioConfiguration = nil
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    previous.category, mode: previous.mode, options: previous.options
                )
            } catch {
                Logger.camera.warning("Failed to restore audio session after recording: \(error.localizedDescription)")
            }
        }

        Logger.camera.debug("Removed audio input")
    }

    // MARK: - Private Methods

    private func configurePhotoOutputForMaxQuality(for device: AVCaptureDevice) {
        output.maxPhotoQualityPrioritization = .quality
        // Allow the largest stills the active format supports instead of the
        // session preset's video resolution — but only at the SAME aspect as
        // the format, so captures keep matching the preview edge-for-edge.
        let format = device.activeFormat
        let feedDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let candidates = format.supportedMaxPhotoDimensions.map { (width: $0.width, height: $0.height) }
        if let best = CameraPreviewLayout.largestDimensions(
            matchingAspectOfWidth: feedDimensions.width,
            height: feedDimensions.height,
            in: candidates
        ) {
            output.maxPhotoDimensions = CMVideoDimensions(width: best.width, height: best.height)
        }
    }
}

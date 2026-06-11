//
//  CameraModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/24/25.
//
@preconcurrency import AVFoundation
import SwiftUI
import FactoryKit
import Logging
import Combine
import CryptoKit

// Camera model that handles the AVFoundation functionality
@MainActor
class CameraViewModel: NSObject, ObservableObject {
    
    // MARK: - Debug/Simulator Detection
    // periphery:ignore
    private var isRunningInSimulator: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    // MARK: - Services

    private let permissionService = CameraPermissionService()
    private let deviceService = CameraDeviceService()
    private let zoomService = CameraZoomService()
    private let focusService = CameraFocusService()
    private let photoService = PhotoCaptureService()
    private let videoService = VideoCaptureService()

    var isPermissionGranted: Bool { permissionService.isPermissionGranted }
    var session: AVCaptureSession { deviceService.session }
    var output: AVCapturePhotoOutput { deviceService.output }
    var currentDevice: AVCaptureDevice? { deviceService.currentDevice }
    var zoomFactor: CGFloat { zoomService.zoomFactor }
    var minZoom: CGFloat { zoomService.minZoom }
    var maxZoom: CGFloat { zoomService.maxZoom }
    var focusIndicatorPoint: CGPoint? { focusService.focusIndicatorPoint }
    var showingFocusIndicator: Bool { focusService.showingFocusIndicator }
    var isSavingPhoto: Bool { photoService.isSavingPhoto }

    // Video capture properties
    var isRecording: Bool { videoService.isRecording }
    var recordingDurationMs: Int64 { videoService.recordingDurationMs }

    @Published var alert = false
    @Published var preview: AVCaptureVideoPreviewLayer!
    @Published var captureMode: CaptureMode = .photo

    // Video encryption state
    @Published var isEncryptingVideo: Bool = false
    @Published var encryptionProgress: Double = 0

    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository

    @Injected(\.videoEncryptionService)
    private var videoEncryptionService: VideoEncryptionService

    @Injected(\.encryptionScheme)
    private var encryptionScheme: EncryptionScheme
    
    
    
    // UI interaction properties
    var viewSize: CGSize = .zero
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    var cameraPosition: AVCaptureDevice.Position { deviceService.cameraPosition }

    // Combine subscriptions
    private var cancellables = Set<AnyCancellable>()



    // Initialize camera with delayed permission check to prevent race conditions
    override init() {
        super.init()

        // Wire video recording callback to trigger encryption
        videoService.onRecordingFinished = { [weak self] outputURL in
            self?.encryptRecordedVideo(at: outputURL)
        }

        // Release the mic once recording fully finalizes (success or failure).
        videoService.onRecordingStopped = { [weak self] in
            self?.deviceService.detachAudioInput()
        }

        // Observe permission changes from the service
        permissionService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe focus service changes
        focusService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe photo service changes
        photoService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe zoom service changes
        zoomService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Observe video service changes
        videoService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Listen for app lifecycle events to restart camera and reset zoom
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
    }

    deinit {
        // Remove our own notification observers
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAppBecameActive() {
        Logger.camera.info("App became active, restarting camera and resetting zoom")
        restartCameraSessionIfNeeded()
        resetZoomLevel()
    }

    @objc private func handleAppWillResignActive() {
        Logger.camera.info("App will resign active, stopping camera")
        // Stop any active recording before stopping session
        if isRecording {
            stopRecording()
        }
        stopCameraSession()
    }

    func restartCameraSessionIfNeeded() {
        let session = self.session
        if !session.isRunning {
            Logger.camera.info("Camera session not running, restarting...")
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    func stopCameraSession() {
        let session = self.session
        if session.isRunning {
            Logger.camera.info("Stopping camera session")
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
    }
    
     
    func checkAndSetupCamera() async {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            // For simulator, just setup camera after a delay
            Task {
                try await Task.sleep(for: .milliseconds(200))
                await setupCamera()
            }
            return
        }
        #endif
        
        // Check and update camera permissions
        let isGranted = await permissionService.checkAndUpdatePermissions()
        
        if isGranted {
            Task {
                try await Task.sleep(for: .milliseconds(200))
                await deviceService.setupCamera(for: cameraPosition)
                zoomService.updateZoomLimits(for: currentDevice)
            }
        } else {
            await MainActor.run {
                self.alert = true
            }
        }
    }
    
    
    // periphery:ignore
    func setupCamera() async {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            await setupSimulatorMockCamera()
            return
        }
        #endif
        
        await deviceService.setupCamera(for: cameraPosition)

        // Update zoom limits based on device
        zoomService.updateZoomLimits(for: currentDevice)
        
        if let device = currentDevice {
            focusService.setupSubjectAreaChangeMonitoring(for: device)
            focusService.startPeriodicFocusCheck(device: device)
            prepareZeroShutterLagCapture()
        }
    }
    
    #if DEBUG && targetEnvironment(simulator)
    // MARK: - Simulator Mock Camera Setup
    private func setupSimulatorMockCamera() async {
        Logger.camera.debug("Setting up mock camera for simulator")
        
        zoomService.updateZoomForSimulator()
    }
    
    
    #endif
    
    
    // periphery:ignore
    private func prepareZeroShutterLagCapture() {
        // TODO/debug
        return
    }
    
    
    func capturePhoto() {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            Task {
                await photoService.captureMockPhoto(cameraPosition: cameraPosition)
            }
            return
        }
        #endif

        photoService.capturePhoto(
            flashMode: flashMode,
            cameraPosition: cameraPosition,
            output: output,
            preview: preview,
            session: session
        )
    }

    // MARK: - Capture Mode & Video Recording

    /// Switch between photo and video capture modes
    func switchCaptureMode(to mode: CaptureMode) {
        guard mode != captureMode else { return }

        // Stop any active recording before switching modes
        if isRecording {
            stopRecording()
        }

        captureMode = mode
        deviceService.configureForMode(mode)

        // Mode switches always start back at the default zoom
        resetZoomLevel()

        Logger.camera.info("Switched capture mode to: \(String(describing: mode))")
    }

    /// Start video recording
    @discardableResult
    func startRecording() -> URL? {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            Logger.camera.warning("Video recording not supported in simulator")
            return nil
        }
        #endif

        guard captureMode == .video else {
            Logger.camera.warning("Cannot start recording - not in video mode")
            return nil
        }

        // Attach the mic only now, immediately before recording — so toggling
        // into video mode never reconfigures the session (no preview flicker)
        // and the mic indicator appears only while actually recording.
        deviceService.attachAudioInput()

        let outputURL = videoService.startRecording(
            session: session,
            movieOutput: deviceService.movieOutput,
            preview: preview
        )

        // If recording never actually started, no finish delegate will fire to
        // release the mic, so release it here.
        if outputURL == nil {
            deviceService.detachAudioInput()
        }

        return outputURL
    }

    /// Stop video recording
    func stopRecording() {
        // The mic is released once finalization completes (onRecordingStopped),
        // not here — removing the input mid-finalization could truncate audio.
        videoService.stopRecording()
    }

    /// Toggle video recording state
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // Smooth zoom with lens-specific adjustments and auto mode restoration
    func zoom(factor: CGFloat) async {
        await zoomService.zoom(factor: factor, device: currentDevice)
    }
    
    // Handle pinch gestures; the virtual device zooms seamlessly across lenses
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat? = nil) {
        zoomService.handlePinchGesture(
            scale: scale,
            initialScale: initialScale,
            device: currentDevice
        )
    }

    // Tap-to-focus with optional white balance locking
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool = false) {
        focusService.adjustCameraSettings(at: point, lockWhiteBalance: lockWhiteBalance, device: currentDevice)
    }

    // Switch between front and back cameras with clean white balance reset
    func switchCamera(to position: AVCaptureDevice.Position) async {
        await deviceService.switchCamera(to: position)

        // Rebuild the zoom mapping for the new device (front cameras have no
        // ultra-wide lens); setupCamera already positioned it at display 1.0x.
        zoomService.updateZoomLimits(for: currentDevice)

        // Set up focus monitoring for the new device
        if let device = currentDevice {
            focusService.setupSubjectAreaChangeMonitoring(for: device)
        }
    }
    
    // Convert device coordinates to view coordinates for UI display
    func showFocusIndicator(on viewPoint: CGPoint) {
        focusService.showFocusIndicator(on: viewPoint)
    }
    
    // Reset zoom level to 1.0 (called when app comes from background)
    func resetZoomLevel() {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            Task { @MainActor in
                self.zoomService.zoomFactor = 1.0
            }
            return
        }
        #endif
        
        zoomService.resetZoomLevel(device: currentDevice)
    }
    
    
    func toggleFlashMode() {
        let currentMode = flashMode
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

        // Cycling the flash mode is a synchronous, idempotent state change — it
        // only takes effect at capture time — so there's nothing to debounce.
        flashMode = newMode

        Logger.camera.debug("Flash mode cycling", metadata: [
            "from": .string(String(describing: currentMode)),
            "to": .string(String(describing: newMode))
        ])
    }
    
    var flashIcon: String {
        switch flashMode {
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

    // MARK: - Video Encryption

    private func encryptRecordedVideo(at movURL: URL) {
        Task {
            do {
                let keyData = try await encryptionScheme.getDerivedKey()
                let symmetricKey = SymmetricKey(data: keyData)

                // Generate the gallery thumbnail from the plaintext .mov now,
                // while it still exists (it is deleted after encryption).
                let videoName = movURL.deletingPathExtension().lastPathComponent
                await secureImageRepository.generateAndStoreVideoThumbnail(
                    forVideoNamed: videoName,
                    fromPlaintextVideo: movURL
                )

                // Build .secv output path alongside the .mov
                let secvURL = movURL.deletingPathExtension().appendingPathExtension(SECVFileFormat.FILE_EXTENSION)

                // Create empty output file (FileHandle(forWritingTo:) requires it to exist)
                FileManager.default.createFile(atPath: secvURL.path, contents: nil)

                isEncryptingVideo = true
                encryptionProgress = 0

                let (progress, _) = videoEncryptionService.encryptVideo(
                    inputURL: movURL,
                    outputURL: secvURL,
                    encryptionKey: symmetricKey
                )

                // Observe progress
                progress
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] value in
                        self?.encryptionProgress = value
                        if value >= 1.0 {
                            self?.isEncryptingVideo = false
                            // Delete the temp .mov file
                            try? FileManager.default.removeItem(at: movURL)
                            Logger.camera.info("Video encrypted and temp file deleted", metadata: [
                                "output": .string(secvURL.lastPathComponent)
                            ])
                        }
                    }
                    .store(in: &cancellables)

            } catch {
                isEncryptingVideo = false
                Logger.camera.error("Failed to encrypt video", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
}

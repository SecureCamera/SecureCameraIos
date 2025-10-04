//
//  CameraModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/24/25.
//
import AVFoundation
import SwiftUI
import FactoryKit
import Logging
import Combine

enum CameraLensType {
    case ultraWide   // 0.5x zoom
    case wideAngle   // 1x zoom (standard)
}

// Camera model that handles the AVFoundation functionality
@MainActor
class CameraViewModel: NSObject, ObservableObject {
    
    // MARK: - Debug/Simulator Detection
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
    
    var isPermissionGranted: Bool { permissionService.isPermissionGranted }
    var session: AVCaptureSession { deviceService.session }
    var output: AVCapturePhotoOutput { deviceService.output }
    var currentDevice: AVCaptureDevice? { deviceService.currentDevice }
    var zoomFactor: CGFloat { zoomService.zoomFactor }
    var minZoom: CGFloat { zoomService.minZoom }
    var maxZoom: CGFloat { zoomService.maxZoom }
    var currentLensType: CameraLensType { zoomService.currentLensType }
    var focusIndicatorPoint: CGPoint? { focusService.focusIndicatorPoint }
    var showingFocusIndicator: Bool { focusService.showingFocusIndicator }
    var recentImage: UIImage? { photoService.recentImage }
    
    @Published var alert = false
    @Published var preview: AVCaptureVideoPreviewLayer!
    
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.clock)
    private var clock: Clock
    
    @Injected(\.locationRepository)
    private var locationRepository: LocationRepository
    
    
    
    // UI interaction properties
    var viewSize: CGSize = .zero
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    var cameraPosition: AVCaptureDevice.Position { deviceService.cameraPosition }
    @Published var isTogglingFlash = false

    // Combine subscriptions
    private var cancellables = Set<AnyCancellable>()



    // Initialize camera with delayed permission check to prevent race conditions
    override init() {
        super.init()

        // Observe permission changes from the service
        permissionService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Listen for app entering foreground to reset zoom level
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    deinit {
        // Remove our own notification observers
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppWillEnterForeground() {
        Logger.camera.debug("App entering foreground, resetting zoom level")
        resetZoomLevel()
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
                await deviceService.setupCamera(for: cameraPosition, lensType: currentLensType)
            }
        } else {
            await MainActor.run {
                self.alert = true
            }
        }
    }
    
    
    func setupCamera() async {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            await setupSimulatorMockCamera()
            return
        }
        #endif
        
        await deviceService.setupCamera(for: cameraPosition, lensType: currentLensType)
        
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
    
    
    private func prepareZeroShutterLagCapture() {
        // TODO/debug
        return
    }
    
    
    // Map device orientations to rotation angles for horizon-level capture
    private func rotationAngle(for orientation: UIDeviceOrientation) -> Double {
        switch orientation {
        case .portrait:              return 90
        case .portraitUpsideDown:    return 270
        case .landscapeLeft:         return 0
        case .landscapeRight:        return 180
        default:                     return 0
        }
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
    
    
    // Smooth zoom with lens-specific adjustments and auto mode restoration
    func zoom(factor: CGFloat) async {
        await zoomService.zoom(factor: factor, device: currentDevice)
    }
    
    // Handle pinch gestures with automatic lens switching and smooth zoom
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat? = nil) {
        zoomService.handlePinchGesture(
            scale: scale,
            initialScale: initialScale,
            device: cameraPosition == .back ? currentDevice : nil,
            onLensSwitch: { [weak self] lensType in
                self?.switchLensType(to: lensType)
            }
        )
    }
    
    // Tap-to-focus with optional white balance locking
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool = false) {
        focusService.adjustCameraSettings(at: point, lockWhiteBalance: lockWhiteBalance, device: currentDevice)
    }
    
    
    // Switch between ultra-wide and wide-angle cameras
    func switchLensType(to lensType: CameraLensType) {
        guard lensType != currentLensType else { return }
        guard cameraPosition == .back || lensType == .wideAngle else { return }
        
        zoomService.updateLensType(lensType)
        deviceService.switchLensType(to: lensType)
        
        // Set up focus monitoring for the new device
        if let device = currentDevice {
            focusService.setupSubjectAreaChangeMonitoring(for: device)
        }
    }
    
    // Switch between front and back cameras with clean white balance reset
    func switchCamera(to position: AVCaptureDevice.Position) async {
        if position == .front && currentLensType == .ultraWide {
            zoomService.updateLensType(.wideAngle)
        }
        
        await deviceService.switchCamera(to: position)
        
        // Update zoom after camera switch
        zoomService.resetZoomLevel(device: currentDevice)
        
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
        // Prevent rapid consecutive toggles
        guard !isTogglingFlash else { 
            Logger.camera.debug("Flash toggle ignored - already in progress")
            return 
        }
        
        isTogglingFlash = true
        
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
        
        Logger.camera.debug("Flash mode cycling", metadata: [
            "from": .string(String(describing: currentMode)),
            "to": .string(String(describing: newMode))
        ])
        
        // Update the flash mode
        flashMode = newMode
        
        Logger.camera.debug("Flash mode updated", metadata: [
            "mode": .string(String(describing: flashMode))
        ])
        
        // Re-enable toggling after a brief delay
        Task {
            try await Task.sleep(for: .milliseconds(100))
            await MainActor.run {
                self.isTogglingFlash = false
            }
        }
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
}

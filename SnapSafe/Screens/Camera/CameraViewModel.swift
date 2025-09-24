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
    // MARK: - Camera Permission Properties
    
    @Published private(set) var isPermissionGranted: Bool = false
    private var isCheckingPermission = false
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    @Published var recentImage: UIImage?
    
    // Zoom and lens configuration
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoom: CGFloat = 0.5
    @Published var maxZoom: CGFloat = 10.0
    private var initialZoom: CGFloat = 1.0
    private var currentDevice: AVCaptureDevice?
    private var wideAngleDevice: AVCaptureDevice?
    private var ultraWideDevice: AVCaptureDevice?
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.clock)
    private var clock: Clock
    
    @Injected(\.locationRepository)
    private var locationRepository: LocationRepository
    
    
    enum CameraLensType {
        case ultraWide   // 0.5x zoom
        case wideAngle   // 1x zoom (standard)
    }
    @Published var currentLensType: CameraLensType = .wideAngle
    
    // UI interaction properties
    var viewSize: CGSize = .zero
    @Published var focusIndicatorPoint: CGPoint? = nil
    @Published var showingFocusIndicator = false
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    
    private var isConfiguring = false
    private var focusResetTimer: Timer?
    private var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    // Setup subject area change monitoring for improved autofocus
    private func setupSubjectAreaChangeMonitoring(for device: AVCaptureDevice) {
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: device)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: device
        )
    }
    
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
                    self?.resetToAutoFocus()
                }
                
            } catch {
                Logger.camera.error("Error refocusing camera", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    // Initialize camera with delayed permission check to prevent race conditions
    override init() {
        super.init()
        
        // Initialize with current permission state synchronously to prevent UI delays
        let currentStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.isPermissionGranted = (currentStatus == .authorized)
        
        // Listen for app entering foreground to reset zoom level
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        
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
        if let device = currentDevice {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: device)
        }
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func handleAppWillEnterForeground() {
        Logger.camera.debug("App entering foreground, resetting zoom level")
        resetZoomLevel()
    }
    
    @objc private func handleAppDidBecomeActive() {
        // Refresh permission state when app becomes active
        // (user might have changed permissions in Settings)
        updatePermissionState()
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
        let isGranted = await checkAndUpdatePermissions()
        
        if isGranted {
            Task {
                try await Task.sleep(for: .milliseconds(200))
                await setupCamera()
            }
        } else {
            await MainActor.run {
                self.alert = true
            }
        }
    }
    
    // Get camera devices with fallback for ultra-wide
    private func ultraWideCamera() -> AVCaptureDevice? {
        if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            return ultraWide
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
    
    private func wideAngleCamera(position: AVCaptureDevice.Position = .back) -> AVCaptureDevice? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
    
    func setupCamera() async {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            await setupSimulatorMockCamera()
            return
        }
        #endif
        
        session.sessionPreset = .photo
        session.automaticallyConfiguresApplicationAudioSession = false
        
        do {
            session.beginConfiguration()
            
            wideAngleDevice = wideAngleCamera(position: cameraPosition)
            
            if cameraPosition == .back {
                ultraWideDevice = ultraWideCamera()
            }
            
            var device: AVCaptureDevice?
            let shouldUseUltraWide = currentLensType == .ultraWide && ultraWideDevice != nil && cameraPosition == .back
            
            if shouldUseUltraWide {
                device = ultraWideDevice
            } else {
                device = wideAngleDevice
                await MainActor.run {
                    self.currentLensType = .wideAngle
                }
            }
            
            guard let device = device else {
                Logger.camera.error("Failed to get camera device", metadata: [
                "position": .string(String(describing: cameraPosition))
            ])
                return
            }
            
            currentDevice = device
            
            // Configure device with optimal camera settings
            try device.lockForConfiguration()
            
            let minZoomValue: CGFloat = 1.0
            let maxZoomValue = min(device.activeFormat.videoMaxZoomFactor, 10.0)
            let defaultZoomValue: CGFloat = 1.0
            
            device.videoZoomFactor = defaultZoomValue
            
            // Enable continuous auto modes with smooth transitions
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                device.isSmoothAutoFocusEnabled = true
                
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .none
                }
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            device.isSubjectAreaChangeMonitoringEnabled = true
            
            device.unlockForConfiguration()
            
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                configurePhotoOutputForMaxQuality()
            }
            
            session.commitConfiguration()
            
            await MainActor.run {
                self.minZoom = minZoomValue
                self.maxZoom = maxZoomValue
                self.zoomFactor = defaultZoomValue
            }
            
            setupSubjectAreaChangeMonitoring(for: device)
            startPeriodicFocusCheck()
            prepareZeroShutterLagCapture()
            
        } catch {
            Logger.camera.error("Error setting up camera", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    #if DEBUG && targetEnvironment(simulator)
    // MARK: - Simulator Mock Camera Setup
    private func setupSimulatorMockCamera() async {
        Logger.camera.debug("Setting up mock camera for simulator")
        
        await MainActor.run {
            self.minZoom = 0.5
            self.maxZoom = 10.0
            self.zoomFactor = 1.0
        }
        
        // Create mock photos for simulator
        createMockPhotos()
    }
    
    private func captureMockPhoto() async {
        Logger.camera.debug("Capturing mock photo in simulator")
        
        // Create a simple colored image for testing
        let size = CGSize(width: 1080, height: 1920)
        let colors: [UIColor] = [.systemBlue, .systemGreen, .systemOrange, .systemPurple, .systemRed]
        let randomColor = colors.randomElement() ?? .systemBlue
        
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        randomColor.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        // Add some text to make it look like a photo
        let text = "Mock Photo\n\(Date().formatted())\nCamera: \(cameraPosition == .back ? "Back" : "Front")"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: UIColor.white,
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        
        let mockImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        // Convert to JPEG data
        guard let imageData = mockImage.jpegData(compressionQuality: 0.8) else {
            Logger.camera.error("Failed to create mock image data")
            return
        }
        
        // Update recent image
        await MainActor.run {
            self.recentImage = mockImage
        }
        
        // Save the mock photo
        saveMockPhoto(imageData)
    }
    
    private func createMockPhotos() {
        Task {
            // Create a few sample photos for the gallery
            let sampleTexts = [
                "Sample Photo 1\nLandscape",
                "Sample Photo 2\nPortrait", 
                "Sample Photo 3\nSquare"
            ]
            
            for (index, text) in sampleTexts.enumerated() {
                let isLandscape = index == 0
                let size = isLandscape ? CGSize(width: 1920, height: 1080) : CGSize(width: 1080, height: 1920)
                let color: UIColor = [.systemBlue, .systemGreen, .systemOrange][index]
                
                UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
                color.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 48, weight: .bold),
                    .foregroundColor: UIColor.white,
                ]
                
                let textSize = text.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: (size.width - textSize.width) / 2,
                    y: (size.height - textSize.height) / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                
                text.draw(in: textRect, withAttributes: attributes)
                
                if let mockImage = UIGraphicsGetImageFromCurrentImageContext(),
                   let _ = mockImage.jpegData(compressionQuality: 0.8) {
                    
                    let locationTaken = self.locationRepository.lastLocation
                    let timestamp = clock.now - Double(index * 3600)
                    let rotation = if isLandscape { 90 } else { 0 }
                    
                    do {
                        let photo = CapturedImage(
                            sensorBitmap: mockImage,
                            timestamp: timestamp,
                            rotationDegrees: rotation
                        )
                        _ = try await secureImageRepository.saveImage(
                            photo,
                            location: locationTaken,
                            applyRotation: true)

                        Logger.camera.debug("Created mock photo", metadata: [
                            "photoIndex": .stringConvertible(index + 1)
                        ])
                    } catch {
                        Logger.camera.error("Error creating mock photo", metadata: [
                            "error": .string(String(describing: error))
                        ])
                    }
                }
                
                UIGraphicsEndImageContext()
            }
        }
    }
    
    private func saveMockPhoto(_ imageData: Data) {
        Task(priority: .userInitiated) { [weak self] in
            
            let locationTaken = self?.locationRepository.lastLocation
            let timestamp = self!.clock.now
            let rotation = 0//if isLandscape { 90 } else { 0 }
            
            let mockImage = UIImage(data: imageData)
            do {
                let photo = CapturedImage(
                    sensorBitmap: mockImage!,
                    timestamp: timestamp,
                    rotationDegrees: rotation
                )
                let newPhotoDef = try await self!.secureImageRepository.saveImage(
                    photo,
                    location: locationTaken,
                    applyRotation: true
                )
                
                Logger.camera.info("Mock photo saved successfully", metadata: [
                    "filename": .string(newPhotoDef.photoName)
                ])
            } catch {
                Logger.camera.error("Error saving mock photo", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    #endif
    
    private func configurePhotoOutputForMaxQuality() {
        output.maxPhotoQualityPrioritization = .quality
    }
    
    private func prepareZeroShutterLagCapture() {
        // TODO/debug
        return
    }
    
    private var focusCheckTimer: Timer?
    
    private func startPeriodicFocusCheck() {
        focusCheckTimer?.invalidate()
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAndOptimizeFocus()
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
                await captureMockPhoto()
            }
            return
        }
        #endif
        
        let photoSettings = createAdvancedPhotoSettings()
        
        // Configure flash based on camera position
        if cameraPosition == .back {
            if output.supportedFlashModes.contains(AVCaptureDevice.FlashMode(rawValue: flashMode.rawValue)!) {
                photoSettings.flashMode = flashMode
            }
        } else {
            photoSettings.flashMode = .off
        }
        
        // Set proper rotation using AVCaptureDevice.RotationCoordinator
        guard let connection = output.connection(with: .video) else {
            output.capturePhoto(with: photoSettings, delegate: self)
            return
        }
        
        guard
            let deviceInput = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })
        else {
            output.capturePhoto(with: photoSettings, delegate: self)
            return
        }
        
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: deviceInput.device,
            previewLayer: preview
        )
        
        connection.videoRotationAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        
        output.capturePhoto(with: photoSettings, delegate: self)
    }
    
    private func createAdvancedPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        return settings
    }
    
    // Smooth zoom with lens-specific adjustments and auto mode restoration
    func zoom(factor: CGFloat) async {
        guard let device = currentDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Restore auto modes during zoom
            if device.isExposureModeSupported(.continuousAutoExposure) && device.exposureMode != .continuousAutoExposure {
                device.exposureMode = .continuousAutoExposure
            }
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) && device.whiteBalanceMode != .continuousAutoWhiteBalance {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            var newZoomFactor = factor
            
            if currentLensType == .ultraWide {
                // Map ultra-wide zoom range (0.5x user-facing to device zoom)
                newZoomFactor = max(0.5, min(newZoomFactor, maxZoom))
                let deviceZoomFactor = (newZoomFactor / 0.5)
                let limitedDeviceZoom = min(deviceZoomFactor, device.activeFormat.videoMaxZoomFactor)
                let currentZoom = device.videoZoomFactor
                let interpolationFactor: CGFloat = 0.3
                let smoothedZoom = currentZoom + (limitedDeviceZoom - currentZoom) * interpolationFactor
                
                device.videoZoomFactor = smoothedZoom
                let userFacingZoom = max(0.5, min(newZoomFactor, maxZoom))
                
                await MainActor.run {
                    self.zoomFactor = userFacingZoom
                }
            } else {
                // Wide-angle zoom with smooth interpolation
                newZoomFactor = max(1.0, min(newZoomFactor, maxZoom))
                let currentZoom = device.videoZoomFactor
                let interpolationFactor: CGFloat = 0.3
                let smoothedZoom = currentZoom + (newZoomFactor - currentZoom) * interpolationFactor
                
                device.videoZoomFactor = smoothedZoom
                
                await MainActor.run {
                    self.zoomFactor = smoothedZoom
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            Logger.camera.error("Error setting zoom", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    // Handle pinch gestures with automatic lens switching and smooth zoom
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat? = nil) {
        if initialScale != nil {
            initialZoom = zoomFactor
        }
        
        let zoomSensitivity: CGFloat = 0.5
        let zoomDelta = pow(scale, zoomSensitivity) - 1.0
        let newZoomFactor = initialZoom + (zoomDelta * (maxZoom - minZoom))
        
        // Determine lens switching thresholds
        let shouldUseUltraWide = newZoomFactor <= 0.9 && cameraPosition == .back
        let shouldUseWideAngle = newZoomFactor > 0.9 || cameraPosition == .front
        
        if shouldUseUltraWide && currentLensType != .ultraWide && ultraWideDevice != nil {
            if let device = currentDevice {
                do {
                    try device.lockForConfiguration()
                    
                    // Prepare auto modes for smooth lens transition
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    
                    device.unlockForConfiguration()
                } catch {
                    Logger.camera.error("Error preparing auto modes before lens switch", metadata: [
                        "error": .string(error.localizedDescription)
                    ])
                }
            }
            
            switchLensType(to: .ultraWide)
        } else if shouldUseWideAngle && currentLensType != .wideAngle && wideAngleDevice != nil {
            if let device = currentDevice {
                do {
                    try device.lockForConfiguration()
                    
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    
                    device.unlockForConfiguration()
                } catch {
                    Logger.camera.error("Error preparing auto modes before lens switch", metadata: [
                        "error": .string(error.localizedDescription)
                    ])
                }
            }
            
            switchLensType(to: .wideAngle)
        } else {
            // Apply zoom with auto mode restoration
            if let device = currentDevice {
                do {
                    try device.lockForConfiguration()
                    
                    if device.isExposureModeSupported(.continuousAutoExposure) && device.exposureMode != .continuousAutoExposure {
                        device.exposureMode = .continuousAutoExposure
                    }
                    
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) && device.whiteBalanceMode != .continuousAutoWhiteBalance {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    
                    device.unlockForConfiguration()
                } catch {
                    // Ignore errors here, it's just optimization
                }
            }
            
            Task {
                await zoom(factor: newZoomFactor)
            }
        }
    }
    
    // Tap-to-focus with optional white balance locking
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool = false) {
        guard let device = currentDevice else { return }
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
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                if lockWhiteBalance {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                    let currentWhiteBalanceGains = device.deviceWhiteBalanceGains
                    device.setWhiteBalanceModeLocked(with: currentWhiteBalanceGains, completionHandler: nil)
                } else {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }
            
            device.unlockForConfiguration()
            
            // Schedule auto-focus reset with appropriate delay
            let resetDelay = lockWhiteBalance ? 8.0 : 3.0
            focusResetTimer = Timer.scheduledTimer(withTimeInterval: resetDelay, repeats: false) { [weak self] _ in
                self?.resetToAutoFocus()
            }
        } catch {
            Logger.camera.error("Error adjusting camera settings", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }
    
    // Return to continuous auto modes after manual adjustments
    private func resetToAutoFocus() {
        guard let device = currentDevice else { return }
        
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
    
    private func normalizeGains(_ gains: AVCaptureDevice.WhiteBalanceGains, for device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        var normalizedGains = gains
        normalizedGains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
        normalizedGains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
        normalizedGains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
        return normalizedGains
    }
    
    // Switch between ultra-wide and wide-angle cameras with white balance preservation
    func switchLensType(to lensType: CameraLensType) {
        guard !isConfiguring else { return }
        
        if lensType == currentLensType || cameraPosition == .front && lensType == .ultraWide {
            return
        }
        
        isConfiguring = true
        
        Task { @MainActor in
            self.currentLensType = lensType
        }
        
        Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            // Capture current white balance settings for smooth transition
            var previousWhiteBalanceGains: AVCaptureDevice.WhiteBalanceGains?
            var previousWhiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance
            
            if let oldDevice = self.currentDevice {
                do {
                    try oldDevice.lockForConfiguration()
                    previousWhiteBalanceMode = oldDevice.whiteBalanceMode
                    previousWhiteBalanceGains = oldDevice.deviceWhiteBalanceGains
                    oldDevice.unlockForConfiguration()
                } catch {
                    Logger.camera.debug("Could not capture white balance from previous device", metadata: [
                        "error": .string(error.localizedDescription)
                    ])
                }
            }
            
            self.session.beginConfiguration()
            
            if let oldDevice = self.currentDevice {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldDevice)
            }
            
            if let inputs = self.session.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    self.session.removeInput(input)
                }
            }
            
            do {
                var device: AVCaptureDevice?
                
                switch lensType {
                case .ultraWide:
                    device = self.ultraWideDevice
                case .wideAngle:
                    device = self.wideAngleDevice
                }
                
                if device == nil {
                    if lensType == .ultraWide && self.wideAngleDevice != nil {
                        self.currentLensType = .wideAngle
                        device = self.wideAngleDevice
                    } else {
                        self.session.commitConfiguration()
                        return
                    }
                }
                
                guard let device = device else {
                    self.session.commitConfiguration()
                    return
                }
                
                self.currentDevice = device
                
                // Configure device with optimal settings and white balance preservation
                try device.lockForConfiguration()
                
                device.videoZoomFactor = 1.0
                
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    device.isSmoothAutoFocusEnabled = true
                    
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .none
                    }
                }
                
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                // Apply white balance transition for smooth lens switching
                if let previousGains = previousWhiteBalanceGains,
                   device.isWhiteBalanceModeSupported(.locked) {
                    let normalizedGains = self.normalizeGains(previousGains, for: device)
                    
                    if previousWhiteBalanceMode == .locked {
                        device.setWhiteBalanceModeLocked(with: normalizedGains) { _ in }
                    } else {
                        device.setWhiteBalanceModeLocked(with: normalizedGains) { _ in
                            Task { @MainActor in
                                try await Task.sleep(for: .milliseconds(500))
                                do {
                                    try device.lockForConfiguration()
                                    if device.isWhiteBalanceModeSupported(previousWhiteBalanceMode) {
                                        device.whiteBalanceMode = previousWhiteBalanceMode
                                    } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                                    }
                                    device.unlockForConfiguration()
                                } catch {
                                    Logger.camera.error("Error restoring white balance mode", metadata: [
                                        "error": .string(error.localizedDescription)
                                    ])
                                }
                            }
                        }
                    }
                } else {
                    if device.isWhiteBalanceModeSupported(previousWhiteBalanceMode) {
                        device.whiteBalanceMode = previousWhiteBalanceMode
                    } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
                
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                }
                
                self.session.commitConfiguration()
                self.setupSubjectAreaChangeMonitoring(for: device)
                self.configurePhotoOutputForMaxQuality()
                self.prepareZeroShutterLagCapture()
                
                if !self.session.isRunning {
                    Task(priority: .userInitiated) {
                        self.session.startRunning()
                    }
                }
                
                self.isConfiguring = false
                
            } catch {
                Logger.camera.error("Error switching lens type", metadata: [
                    "error": .string(error.localizedDescription)
                ])
                self.session.commitConfiguration()
                self.isConfiguring = false
            }
        }
    }
    
    // Switch between front and back cameras with clean white balance reset
    func switchCamera(to position: AVCaptureDevice.Position) async {
        guard !isConfiguring else { return }
        
        if position == cameraPosition && currentDevice != nil {
            return
        }
        
        isConfiguring = true
        
        await MainActor.run {
            self.cameraPosition = position
        }
        
        let currentLensTypeSnapshot = currentLensType
        
        if position == .front && currentLensTypeSnapshot == .ultraWide {
            await MainActor.run {
                self.currentLensType = .wideAngle
            }
        }
        
        Task(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            
            if let oldDevice = self.currentDevice {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldDevice)
            }
            
            if let inputs = self.session.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    self.session.removeInput(input)
                }
            }
            
            do {
                // Update available devices for new position
                self.wideAngleDevice = self.wideAngleCamera(position: position)
                
                if position == .back {
                    self.ultraWideDevice = self.ultraWideCamera()
                } else {
                    self.ultraWideDevice = nil
                }
                
                var device: AVCaptureDevice?
                if position == .back && currentLensType == .ultraWide && ultraWideDevice != nil {
                    device = ultraWideDevice
                } else {
                    device = wideAngleDevice
                    if position == .front {
                        await MainActor.run {
                            self.currentLensType = .wideAngle
                        }
                    }
                }
                
                guard let device = device else {
                    self.session.commitConfiguration()
                    return
                }
                
                self.currentDevice = device
                
                // Configure device with fresh auto white balance for new camera position
                try device.lockForConfiguration()
                
                device.videoZoomFactor = 1.0
                
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    device.isSmoothAutoFocusEnabled = true
                    
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .none
                    }
                }
                
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                
                // Use clean auto white balance for front/back switches
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = true
                device.unlockForConfiguration()
                
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                }
                
                self.session.commitConfiguration()
                self.setupSubjectAreaChangeMonitoring(for: device)
                self.configurePhotoOutputForMaxQuality()
                self.prepareZeroShutterLagCapture()
                
                await MainActor.run {
                    self.zoomFactor = 1.0
                }
                
                if !self.session.isRunning {
                    Task(priority: .userInitiated) {
                        self.session.startRunning()
                    }
                }
                
                self.isConfiguring = false
                
            } catch {
                Logger.camera.error("Error switching camera", metadata: [
                    "error": .string(error.localizedDescription)
                ])
                self.session.commitConfiguration()
                self.isConfiguring = false
            }
        }
    }
    
    // Convert device coordinates to view coordinates for UI display
    func showFocusIndicator(on viewPoint: CGPoint) {
        Task { @MainActor in
            self.focusIndicatorPoint = viewPoint
            self.showingFocusIndicator = true
            
            try await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { 
                self.showingFocusIndicator = false 
            }
        }
    }
    
    // Reset zoom level to 1.0 (called when app comes from background)
    func resetZoomLevel() {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            Task { @MainActor in
                self.zoomFactor = 1.0
            }
            return
        }
        #endif
        
        guard let device = currentDevice else { return }
        
        Task(priority: .userInitiated) {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = 1.0
                device.unlockForConfiguration()
                
                await MainActor.run {
                    self.zoomFactor = 1.0
                }
            } catch {
                Logger.camera.error("Error resetting zoom level", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    // MARK: - Camera Permission Methods
    
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
    
    private func updatePermissionState(granted: Bool) {
        Task { @MainActor in
            self.isPermissionGranted = granted
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            Logger.camera.error("Error capturing photo", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            Logger.camera.error("Failed to get image data")
            return
        }

        savePhoto(imageData)

        if let image = UIImage(data: imageData) {
            Task { @MainActor in
                self.recentImage = image
            }
        }
    }
    
    // Handle deferred photo processing with instant preview
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        guard error == nil else {
            Logger.camera.error("Error with deferred photo", metadata: [
                "error": .string(error!.localizedDescription)
            ])
            return
        }
        
        if let previewPixelBuffer = proxy?.previewPixelBuffer {
            let ciImage = CIImage(cvPixelBuffer: previewPixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let previewImage = UIImage(cgImage: cgImage)
                
                Task { @MainActor in
                    self.recentImage = previewImage
                }
            }
        }
    }

    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        _ = image.imageOrientation
        
        if image.imageOrientation == .up {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }

    // Save photo with metadata extraction and secure storage
    private func savePhoto(_ imageData: Data) {
        Task(priority: .userInitiated) { [weak self] in
            var metadata: [String: Any] = [:]

            if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
               let imageMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                metadata = imageMetadata
                
                // Extract and preserve orientation information
                var exifOrientation: Int = 1
                
                if let exifDict = metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
                   let orientation = exifDict[String(kCGImagePropertyOrientation)] as? Int {
                    exifOrientation = orientation
                }
                else if let tiffDict = metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any],
                        let orientation = tiffDict[String(kCGImagePropertyTIFFOrientation)] as? Int {
                    exifOrientation = orientation
                }
                
                metadata["originalOrientation"] = exifOrientation
                //metadata["cameraPosition"] = self.cameraPosition == .front ? "front" : "back"
                
                // Determine landscape orientation based on dimensions and rotation
                if let pixelWidth = metadata[String(kCGImagePropertyPixelWidth)] as? Int,
                   let pixelHeight = metadata[String(kCGImagePropertyPixelHeight)] as? Int {
                    
                    let isRotated = (exifOrientation >= 5 && exifOrientation <= 8)
                    
                    if isRotated {
                        metadata["isLandscape"] = pixelHeight > pixelWidth
                    } else {
                        metadata["isLandscape"] = pixelWidth > pixelHeight
                    }
                }
            }
            
            let timestamp = self?.clock.now
            let rotation = 0
            let photo = UIImage(data: imageData)
            
            let image = CapturedImage(
                sensorBitmap: photo!,
                timestamp: timestamp!,
                rotationDegrees: rotation
            )
            let locationTaken = self?.locationRepository.lastLocation ?? nil
            
            do {
                let photoDef = try await self?.secureImageRepository.saveImage(
                    image,
                    location: locationTaken,
                    applyRotation: true
                )
                Logger.camera.info("Photo saved successfully", metadata: [
                    "filename": .string(photoDef?.photoName ?? "unknown")
                ])
            } catch {
                Logger.camera.error("Error saving photo", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
}

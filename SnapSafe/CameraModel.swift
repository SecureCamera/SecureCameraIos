//
//  CameraModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/24/25.
//
import AVFoundation
import SwiftUI

// Camera model that handles the AVFoundation functionality
class CameraModel: NSObject, ObservableObject {
    
    // MARK: - Debug/Simulator Detection
    private var isRunningInSimulator: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    @Published var isPermissionGranted = false
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
                print("Error refocusing: \(error.localizedDescription)")
            }
        }
    }
    
    private let secureFileManager = SecureFileManager()
    
    // Initialize camera with delayed permission check to prevent race conditions
    override init() {
        super.init()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                self.checkPermissions()
            }
        }
    }
    
    deinit {
        if let device = currentDevice {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: device)
        }
    }
    
    func checkPermissions() {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            DispatchQueue.main.async {
                self.isPermissionGranted = true
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                self.setupCamera()
            }
            return
        }
        #endif
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.isPermissionGranted = true
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                self.setupCamera()
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { status in
                if status {
                    DispatchQueue.main.async {
                        self.isPermissionGranted = true
                    }
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                        self.setupCamera()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.isPermissionGranted = false
                        self.alert = true
                    }
                }
            }
        default:
            DispatchQueue.main.async {
                self.isPermissionGranted = false
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
    
    func setupCamera() {
        #if DEBUG && targetEnvironment(simulator)
        if isRunningInSimulator {
            setupSimulatorMockCamera()
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
                DispatchQueue.main.async {
                    self.currentLensType = .wideAngle
                }
            }
            
            guard let device = device else {
                print("Failed to get camera device for position: \(cameraPosition)")
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
            
            DispatchQueue.main.async {
                self.minZoom = minZoomValue
                self.maxZoom = maxZoomValue
                self.zoomFactor = defaultZoomValue
            }
            
            setupSubjectAreaChangeMonitoring(for: device)
            startPeriodicFocusCheck()
            prepareZeroShutterLagCapture()
            
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    #if DEBUG && targetEnvironment(simulator)
    // MARK: - Simulator Mock Camera Setup
    private func setupSimulatorMockCamera() {
        print("Setting up mock camera for simulator")
        
        DispatchQueue.main.async {
            self.minZoom = 0.5
            self.maxZoom = 10.0
            self.zoomFactor = 1.0
        }
        
        // Create mock photos for simulator
        createMockPhotos()
    }
    
    private func captureMockPhoto() {
        print("Capturing mock photo in simulator")
        
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
            print("Failed to create mock image data")
            return
        }
        
        // Update recent image
        DispatchQueue.main.async {
            self.recentImage = mockImage
        }
        
        // Save the mock photo
        saveMockPhoto(imageData)
    }
    
    private func createMockPhotos() {
        DispatchQueue.global(qos: .background).async {
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
                   let imageData = mockImage.jpegData(compressionQuality: 0.8) {
                    
                    let metadata: [String: Any] = [
                        "creationDate": Date().timeIntervalSince1970 - Double(index * 3600), // Stagger by hours
                        "cameraPosition": "back",
                        "isLandscape": isLandscape,
                        "mockPhoto": true
                    ]
                    
                    do {
                        _ = try self.secureFileManager.savePhoto(imageData, withMetadata: metadata)
                        print("Created mock photo \(index + 1)")
                    } catch {
                        print("Error creating mock photo: \(error)")
                    }
                }
                
                UIGraphicsEndImageContext()
            }
        }
    }
    
    private func saveMockPhoto(_ imageData: Data) {
        DispatchQueue.global(qos: .userInitiated).async {
            let metadata: [String: Any] = [
                "creationDate": Date().timeIntervalSince1970,
                "cameraPosition": self.cameraPosition == .front ? "front" : "back",
                "isLandscape": false, // Mock photos are portrait by default
                "mockPhoto": true
            ]
            
            do {
                let filename = try self.secureFileManager.savePhoto(imageData, withMetadata: metadata)
                print("Mock photo saved successfully: \(filename)")
            } catch {
                print("Error saving mock photo: \(error.localizedDescription)")
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
                print("Error in focus check: \(error.localizedDescription)")
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
            captureMockPhoto()
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
    func zoom(factor: CGFloat) {
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
                
                DispatchQueue.main.async {
                    self.zoomFactor = userFacingZoom
                }
            } else {
                // Wide-angle zoom with smooth interpolation
                newZoomFactor = max(1.0, min(newZoomFactor, maxZoom))
                let currentZoom = device.videoZoomFactor
                let interpolationFactor: CGFloat = 0.3
                let smoothedZoom = currentZoom + (newZoomFactor - currentZoom) * interpolationFactor
                
                device.videoZoomFactor = smoothedZoom
                
                DispatchQueue.main.async {
                    self.zoomFactor = smoothedZoom
                }
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom: \(error.localizedDescription)")
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
                    print("📸 Error preparing auto modes before lens switch: \(error.localizedDescription)")
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
                    print("📸 Error preparing auto modes before lens switch: \(error.localizedDescription)")
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
            
            zoom(factor: newZoomFactor)
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
            print("Error adjusting camera settings: \(error.localizedDescription)")
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
            print("Error resetting focus: \(error.localizedDescription)")
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
        
        DispatchQueue.main.async {
            self.currentLensType = lensType
        }
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
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
                    print("📸 Could not capture white balance from previous device: \(error.localizedDescription)")
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
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                do {
                                    try device.lockForConfiguration()
                                    if device.isWhiteBalanceModeSupported(previousWhiteBalanceMode) {
                                        device.whiteBalanceMode = previousWhiteBalanceMode
                                    } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                                    }
                                    device.unlockForConfiguration()
                                } catch {
                                    print("📸 Error restoring white balance mode: \(error.localizedDescription)")
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
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.session.startRunning()
                    }
                }
                
                self.isConfiguring = false
                
            } catch {
                print("📸 Error switching lens type: \(error.localizedDescription)")
                self.session.commitConfiguration()
                self.isConfiguring = false
            }
        }
    }
    
    // Switch between front and back cameras with clean white balance reset
    func switchCamera(to position: AVCaptureDevice.Position) {
        guard !isConfiguring else { return }
        
        if position == cameraPosition && currentDevice != nil {
            return
        }
        
        isConfiguring = true
        
        DispatchQueue.main.async {
            self.cameraPosition = position
        }
        
        let currentLensTypeSnapshot = currentLensType
        
        if position == .front && currentLensTypeSnapshot == .ultraWide {
            DispatchQueue.main.async {
                self.currentLensType = .wideAngle
            }
        }
        
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            // Capture white balance for reference (though typically not preserved for front/back switches)
            var previousWhiteBalanceGains: AVCaptureDevice.WhiteBalanceGains?
            
            if let oldDevice = self.currentDevice {
                do {
                    try oldDevice.lockForConfiguration()
                    previousWhiteBalanceGains = oldDevice.deviceWhiteBalanceGains
                    oldDevice.unlockForConfiguration()
                } catch {
                    print("📸 Could not capture white balance from previous device: \(error.localizedDescription)")
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
                        DispatchQueue.main.async {
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
                
                DispatchQueue.main.async {
                    self.zoomFactor = 1.0
                }
                
                if !self.session.isRunning {
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.session.startRunning()
                    }
                }
                
                self.isConfiguring = false
                
            } catch {
                print("📸 Error switching camera: \(error.localizedDescription)")
                self.session.commitConfiguration()
                self.isConfiguring = false
            }
        }
    }
    
    // Convert device coordinates to view coordinates for UI display
    func showFocusIndicator(on viewPoint: CGPoint) {
        DispatchQueue.main.async {
            self.focusIndicatorPoint = viewPoint
            self.showingFocusIndicator = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeOut(duration: 0.3)) { self.showingFocusIndicator = false }
            }
        }
    }
}
    // Photo capture delegate with metadata preservation and secure storage
    extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            print("Failed to get image data")
            return
        }

        savePhoto(imageData)

        if let image = UIImage(data: imageData) {
            DispatchQueue.main.async {
                self.recentImage = image
            }
        }
    }
    
    // Handle deferred photo processing with instant preview
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        guard error == nil else {
            print("Error with deferred photo: \(error!.localizedDescription)")
            return
        }
        
        if let previewPixelBuffer = proxy?.previewPixelBuffer {
            let ciImage = CIImage(cvPixelBuffer: previewPixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let previewImage = UIImage(cgImage: cgImage)
                
                DispatchQueue.main.async {
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
        DispatchQueue.global(qos: .userInitiated).async {
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
                metadata["cameraPosition"] = self.cameraPosition == .front ? "front" : "back"
                
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
            
            do {
                let filename = try self.secureFileManager.savePhoto(imageData, withMetadata: metadata)
                print("Photo saved successfully with timestamp filename: \(filename)")
            } catch {
                print("Error saving photo: \(error.localizedDescription)")
            }
        }
    }
}

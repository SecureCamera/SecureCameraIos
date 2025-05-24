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
    @Published var isPermissionGranted = false
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    @Published var recentImage: UIImage?

    // Zoom properties
    @Published var zoomFactor: CGFloat = 1.0
    @Published var minZoom: CGFloat = 0.5
    @Published var maxZoom: CGFloat = 10.0
    private var initialZoom: CGFloat = 1.0
    private var currentDevice: AVCaptureDevice?
    
    // Camera lens options
    private var wideAngleDevice: AVCaptureDevice?
    private var ultraWideDevice: AVCaptureDevice?
    
    // Current lens type
    enum CameraLensType {
        case ultraWide   // 0.5x zoom
        case wideAngle   // 1x zoom (standard)
    }
    @Published var currentLensType: CameraLensType = .wideAngle

    // View size for coordinate mapping
    var viewSize: CGSize = .zero

    // Focus indicator properties
    @Published var focusIndicatorPoint: CGPoint? = nil
    @Published var showingFocusIndicator = false

    // Flash control
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    
    // Camera position (front or back)
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    
    // ADD: Configuration state to prevent race conditions
    private var isConfiguring = false

    // Timer to reset to auto-focus mode after tap-to-focus
    private var focusResetTimer: Timer?
    
    // Last focus point for refocusing on subject area change
    private var lastFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5) // Default to center
    
    // Setup subject area change monitoring
    private func setupSubjectAreaChangeMonitoring(for device: AVCaptureDevice) {
        // Remove any existing observer first to avoid duplicates
        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: device)
        
        // Add observer for subject area changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(subjectAreaDidChange),
            name: .AVCaptureDeviceSubjectAreaDidChange,
            object: device
        )
        
        print("📸 Subject area change monitoring set up for device: \(device.localizedName)")
    }
    
    // Handle subject area changes
    @objc private func subjectAreaDidChange(notification: Notification) {
        // When the subject area changes, refocus to the last focus point or center
        print("📸 Subject area changed, refocusing")
        refocusCamera()
    }
    
    // Refocus camera after subject area change
    private func refocusCamera() {
        guard let device = currentDevice else { return }
        
        // Use last known focus point or default to center
        let focusPoint = lastFocusPoint
        
        do {
            try device.lockForConfiguration()
            
            // Set focus point and mode if supported
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = focusPoint
                device.focusMode = .autoFocus
                print("📸 Refocusing to point: \(focusPoint.x), \(focusPoint.y)")
            }
            
            // Set exposure point and mode if supported
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .autoExpose
            }
            
            device.unlockForConfiguration()
            
            // Show visual feedback for refocusing
            showFocusIndicator(at: focusPoint)
            
            // Schedule return to continuous auto modes after a delay
            focusResetTimer?.invalidate()
            focusResetTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.resetToAutoFocus()
            }
            
        } catch {
            print("Error refocusing: \(error.localizedDescription)")
        }
    }

    // Storage managers
    private let secureFileManager = SecureFileManager()

    // Initialize as part of class creation with more careful setup
    override init() {
        super.init()
        
        // Since this is a class, we can use self directly, but we'll still be careful
        // with the reference to avoid any potential retain cycles
        
        // Initialize with a small delay to ensure everything is ready
        // This helps prevent race conditions in app startup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Begin checking permissions on a background thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                print("📸 Starting camera permission check")
                self.checkPermissions()
            }
        }
    }
    
    deinit {
        // Clean up notification observers when deallocated
        if let device = currentDevice {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: device)
        }
    }

    func checkPermissions() {
        print("📸 Checking camera permissions...")
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Update @Published property on main thread
            DispatchQueue.main.async {
                self.isPermissionGranted = true
            }
            // Set up on a background thread with slight delay to ensure UI is ready
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                print("📸 Permission already granted, setting up camera")
                self.setupCamera()
            }
        case .notDetermined:
            // Request permission
            print("📸 Requesting camera permission from user")
            AVCaptureDevice.requestAccess(for: .video) { status in
                if status {
                    // Update @Published property on main thread
                    DispatchQueue.main.async {
                        self.isPermissionGranted = true
                    }
                    // Setup on a background thread with slight delay
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2) {
                        print("📸 Permission granted, setting up camera")
                        self.setupCamera()
                    }
                } else {
                    // If permission denied, update UI on main thread
                    DispatchQueue.main.async {
                        self.isPermissionGranted = false
                        self.alert = true
                        print("📸 Camera permission denied by user")
                    }
                }
            }
        default:
            // Update @Published properties on main thread
            DispatchQueue.main.async {
                self.isPermissionGranted = false
                self.alert = true
                print("📸 Camera permission previously denied")
            }
        }
    }

    // Get the ultra-wide camera device (0.5x zoom)
    private func ultraWideCamera() -> AVCaptureDevice? {
        if let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) {
            return ultraWide // 0.5× lens
        }
        // Fallback (every iPhone has at least a wide-angle lens)
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
    
    // Get the wide-angle camera device (1x zoom)
    private func wideAngleCamera(position: AVCaptureDevice.Position = .back) -> AVCaptureDevice? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }
    
    func setupCamera() {
        // Pre-configure an optimal camera session
        session.sessionPreset = .photo
        session.automaticallyConfiguresApplicationAudioSession = false

        do {
            session.beginConfiguration()

            // Find available camera devices
            wideAngleDevice = wideAngleCamera(position: cameraPosition)
            
            // Only search for ultra-wide camera when using back camera
            if cameraPosition == .back {
                ultraWideDevice = ultraWideCamera()
                print("📸 Ultra-wide camera available: \(ultraWideDevice != nil)")
            }
            
            // Set the initial device based on lens type
            var device: AVCaptureDevice?
            
            let shouldUseUltraWide = currentLensType == .ultraWide && ultraWideDevice != nil && cameraPosition == .back
            
            if shouldUseUltraWide {
                device = ultraWideDevice
                print("📸 Using ultra-wide camera")
            } else {
                device = wideAngleDevice
                // Update the published property on main thread
                DispatchQueue.main.async {
                    self.currentLensType = .wideAngle  // Ensure we're using the correct lens type
                }
                print("📸 Using wide-angle camera")
            }
            
            guard let device = device else {
                print("Failed to get camera device for position: \(cameraPosition)")
                return
            }

            // Store device reference for zoom functionality
            currentDevice = device

            // Configure device for video zoom and focus with optimal settings
            try device.lockForConfiguration()

            // Get zoom values from the device
            let minZoomValue: CGFloat = 1.0
            let maxZoomValue = min(device.activeFormat.videoMaxZoomFactor, 10.0) // Limit to 10x
            let defaultZoomValue: CGFloat = 1.0

            // Set zoom factor on the device
            device.videoZoomFactor = defaultZoomValue

            // Configure continuous auto-focus for optimal performance
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus

                // Enable smooth auto-focus for better transitions
                device.isSmoothAutoFocusEnabled = true

                // Set auto-focus range restriction for better general focusing
                // .none allows the camera to focus on any distance
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .none
                }

                print("📸 Enabled continuous auto-focus with smooth transitions")
            }

            // Enable continuous auto-exposure
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                print("Enabled continuous auto-exposure")
                // Use a faster shutter speed (1/500 sec) for sharper images
                let fastShutter = CMTime(value: 1, timescale: 500) // 1/500 sec
                // Set ISO to a reasonable value (or max if needed)
                let iso = min(device.activeFormat.maxISO, 400)
                
                // Only set custom exposure if we're in good lighting conditions
                // This check helps avoid overly dark images in low light
                if device.exposureDuration.seconds < 0.1 { // Current exposure is faster than 1/10s
                    print("📸 Setting shutter-priority exposure: 1/500s, ISO: \(iso)")
                    device.setExposureModeCustom(duration: fastShutter, iso: iso) { _ in
                        // After setting custom exposure, lock it to prevent auto changes
                        try? device.lockForConfiguration()
                        device.exposureMode = .locked
                        device.unlockForConfiguration()
                    }
                }
            }

            // Enable continuous auto white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("📸 Enabled continuous auto white balance")
            }
            
            // Enable subject area change monitoring for better focus
            device.isSubjectAreaChangeMonitoringEnabled = true
            print("📸 Enabled subject area change monitoring")

            device.unlockForConfiguration()

            // Create and add input
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }

            // Add photo output with high-quality settings
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
            
            // Set up subject area change monitoring
            setupSubjectAreaChangeMonitoring(for: device)

            // Start a periodic task to check and adjust focus if needed
            startPeriodicFocusCheck()
            prepareZeroShutterLagCapture()
            
            // Note: We DO NOT start the session here anymore.
            // The session is started in the CameraPreviewView's makeCoordinator method
            // after all configuration is complete.


        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    private func configurePhotoOutputForMaxQuality() {
        output.maxPhotoQualityPrioritization = .quality
    }

    private func prepareZeroShutterLagCapture() {
        // TODO/debug
        return
        // Check if fast capture prioritization is supported
//        if output.isFastCapturePrioritizationSupported {
//            print("Fast capture prioritization is supported, preparing zero shutter lag pipeline")
//            let zslSettings = AVCapturePhotoSettings()
//            output.setPreparedPhotoSettingsArray([zslSettings])
//        } else {
//            print("Fast capture prioritization is not supported on this device")
//        }
    }

    private var focusCheckTimer: Timer?

    private func startPeriodicFocusCheck() {
        focusCheckTimer?.invalidate()
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAndOptimizeFocus()
        }
    }

    // Check focus conditions and optimize if needed
    private func checkAndOptimizeFocus() {
        guard let device = currentDevice else { return }

        // Only run if we're not in a user-defined focus mode
        if device.focusMode != .locked {
            // We could add scene analysis logic here to determine optimal focus
            // For now, we'll just ensure we're in continuous auto-focus mode

            do {
                try device.lockForConfiguration()

                // Make sure auto-focus is still active
                if device.focusMode != .continuousAutoFocus && device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    print("📸 Re-enabled continuous auto-focus")
                }

                device.unlockForConfiguration()
            } catch {
                print("Error in focus check: \(error.localizedDescription)")
            }
        }
    }
    
    // Helper: map legacy orientations to a rotation angle (deg, CW)
    private func rotationAngle(for orientation: UIDeviceOrientation) -> Double {
        switch orientation {
        case .portrait:              return 90          // device upright → rotate CW so horizon is level
        case .portraitUpsideDown:    return 270
        case .landscapeLeft:         return 0           // lens at top
        case .landscapeRight:        return 180         // lens at bottom
        default:                     return 0
        }
    }

    func capturePhoto() {
        // Create advanced photo settings
        let photoSettings = createAdvancedPhotoSettings()
        
        // Configure flash based on camera position
        if cameraPosition == .back {
            if output.supportedFlashModes.contains(AVCaptureDevice.FlashMode(rawValue: flashMode.rawValue)!) {
                photoSettings.flashMode = flashMode
                print("📸 Using flash mode: \(flashMode)")
            } else {
                print("📸 Flash not supported for requested mode: \(flashMode)")
            }
        } else {
            photoSettings.flashMode = .off
            print("📸 Flash disabled for front camera")
        }

        // Get the video connection for proper rotation
        guard let connection = output.connection(with: .video) else {
            output.capturePhoto(with: photoSettings, delegate: self)
            return
        }
        
        // Find the camera device for the rotation coordinator
        guard
            let deviceInput = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })
        else {
            output.capturePhoto(with: photoSettings, delegate: self)
            return
        }

        // Use AVCaptureDevice.RotationCoordinator for proper image rotation
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: deviceInput.device, 
            previewLayer: preview // Use our preview layer for accurate coordination
        )
        
        // Set the rotation angle for proper horizon-level capture
        connection.videoRotationAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        print("Setting rotation angle from coordinator = \(connection.videoRotationAngle)°")
        
        // Capture the photo with the configured settings
        output.capturePhoto(with: photoSettings, delegate: self)
    }
    
    private func createAdvancedPhotoSettings() -> AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality

//        if output.isStillImageStabilizationSupported {
//            settings.isAutoStillImageStabilizationEnabled = true
//            print("📸 Enabled still image stabilization")
//        }

        return settings
    }

    // Method to handle zoom with smooth animation
    func zoom(factor: CGFloat) {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            // Calculate new zoom factor
            var newZoomFactor = factor
            
            // Apply lens-specific zoom adjustments
            if currentLensType == .ultraWide {
                // For ultra-wide camera, we want 0.5x to appear as 0.5x to the user
                // but the device itself doesn't need zoom factor adjustment
                newZoomFactor = max(0.5, min(newZoomFactor, maxZoom))
                
                // Map the user-facing zoom range to the actual device zoom range
                // Ultra-wide at 0.5x = device at 1.0x
                let deviceZoomFactor = (newZoomFactor / 0.5)
                
                // Limit zoom factor to device's range
                let limitedDeviceZoom = min(deviceZoomFactor, device.activeFormat.videoMaxZoomFactor)
                
                // Get the current factor for interpolation
                let currentZoom = device.videoZoomFactor
                
                // Apply smooth animation through interpolation
                let interpolationFactor: CGFloat = 0.3 // Lower = smoother but slower
                let smoothedZoom = currentZoom + (limitedDeviceZoom - currentZoom) * interpolationFactor
                
                // Set the zoom factor with the smoothed value
                device.videoZoomFactor = smoothedZoom
                
                // Calculate the user-facing zoom factor (0.5x - maxZoom)
                let userFacingZoom = max(0.5, min(newZoomFactor, maxZoom))
                
                // Always update published values on the main thread
                DispatchQueue.main.async {
                    self.zoomFactor = userFacingZoom
                }
            } else {
                // For wide-angle camera, limit zoom factor to device's range
                newZoomFactor = max(1.0, min(newZoomFactor, maxZoom))
                
                // Get the current factor for interpolation
                let currentZoom = device.videoZoomFactor
                
                // Apply smooth animation through interpolation
                // This makes the zoom change more gradually
                let interpolationFactor: CGFloat = 0.3 // Lower = smoother but slower
                let smoothedZoom = currentZoom + (newZoomFactor - currentZoom) * interpolationFactor
                
                // Set the zoom factor with the smoothed value
                device.videoZoomFactor = smoothedZoom
                
                // Always update published values on the main thread
                DispatchQueue.main.async {
                    self.zoomFactor = smoothedZoom
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("Error setting zoom: \(error.localizedDescription)")
        }
    }

    // Method to handle pinch gesture for zoom with smoothing
    func handlePinchGesture(scale: CGFloat, initialScale: CGFloat? = nil) {
        if initialScale != nil {
            // When gesture begins, store the initial zoom
            initialZoom = zoomFactor
        }

        // Calculate a zoom factor with reduced sensitivity to create smoother zooming
        // The 0.5 factor makes the zoom less sensitive, meaning a larger pinch is needed to get to max zoom
        let zoomSensitivity: CGFloat = 0.5
        let zoomDelta = pow(scale, zoomSensitivity) - 1.0

        // Calculate the new zoom factor with a smoother progression
        // Start from the initial zoom when the gesture began
        let newZoomFactor = initialZoom + (zoomDelta * (maxZoom - minZoom))
        
        // Calculate whether we need to switch cameras based on new zoom factor
        let shouldUseUltraWide = newZoomFactor <= 0.9 && cameraPosition == .back
        let shouldUseWideAngle = newZoomFactor > 0.9 || cameraPosition == .front
        
        // Check if we need to switch camera types
        if shouldUseUltraWide && currentLensType != .ultraWide && ultraWideDevice != nil {
            print("📸 Switching to ultra-wide camera (0.5x)")
            switchLensType(to: .ultraWide)
        } else if shouldUseWideAngle && currentLensType != .wideAngle && wideAngleDevice != nil {
            print("📸 Switching to wide-angle camera (1x)")
            switchLensType(to: .wideAngle)
        } else {
            // No camera switch needed, just apply zoom with animation for smoothness
            zoom(factor: newZoomFactor)
        }
    }

    // Method to handle white balance and focus adjustment at a specific point
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool = false) {
        guard let device = currentDevice else { return }

        // Log original coordinates
        print("🎯 Request to focus at device coordinates: \(point.x), \(point.y), lockWhiteBalance: \(lockWhiteBalance)")

        // Store this as the last focus point for subject area change refocusing
        lastFocusPoint = point
        
        // Cancel any existing focus reset timer
        focusResetTimer?.invalidate()

        do {
            try device.lockForConfiguration()

            // Set focus point and mode
            if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
                print("📸 Set focus point to \(point.x), \(point.y)")

                // Enable smooth auto-focus to help with depth of field transitions
                if device.isSmoothAutoFocusSupported {
                    device.isSmoothAutoFocusEnabled = true
                }
            }

            // Set exposure point and mode
            if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
                print("📸 Set exposure point to \(point.x), \(point.y)")
            }

            // Handle white balance differently based on whether we're locking it or not
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                if lockWhiteBalance {
                    // For double-tap: First set to auto white balance to get the right values
                    device.whiteBalanceMode = .continuousAutoWhiteBalance

                    // Then immediately lock it at current value
                    let currentWhiteBalanceGains = device.deviceWhiteBalanceGains
                    device.setWhiteBalanceModeLocked(with: currentWhiteBalanceGains, completionHandler: nil)
                    print("📸 Locked white balance at \(point.x), \(point.y)")
                } else {
                    // For single-tap: Just use auto white balance
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                    print("📸 Set white balance to auto at \(point.x), \(point.y)")
                }
            }

            device.unlockForConfiguration()

            // Schedule return to continuous auto focus after delay
            // Use a shorter delay (3s) for normal focus, longer (8s) for locked white balance
            let resetDelay = lockWhiteBalance ? 8.0 : 3.0
            focusResetTimer = Timer.scheduledTimer(withTimeInterval: resetDelay, repeats: false) { [weak self] _ in
                self?.resetToAutoFocus()
            }

            // Visual feedback with correctly positioned indicator
            // We must convert the point for UI display since it's in device coordinates (0-1)
            showFocusIndicator(at: point)

        } catch {
            print("Error adjusting camera settings: \(error.localizedDescription)")
        }
    }

    // Reset to continuous auto-focus after tap-to-focus
    private func resetToAutoFocus() {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            // Return to continuous auto-focus
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                print("📸 Reset to continuous auto-focus")
            }

            // Return to continuous auto-exposure
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            // Return to continuous auto white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.unlockForConfiguration()
        } catch {
            print("Error resetting focus: \(error.localizedDescription)")
        }
    }

    // ADD: Helper to ensure white balance gains are within device-supported range
    private func normalizeGains(_ gains: AVCaptureDevice.WhiteBalanceGains, for device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        var normalizedGains = gains
        normalizedGains.redGain = max(1.0, min(gains.redGain, device.maxWhiteBalanceGain))
        normalizedGains.greenGain = max(1.0, min(gains.greenGain, device.maxWhiteBalanceGain))
        normalizedGains.blueGain = max(1.0, min(gains.blueGain, device.maxWhiteBalanceGain))
        return normalizedGains
    }
    
    // Switch between ultra-wide and wide-angle cameras
    func switchLensType(to lensType: CameraLensType) {
        // Prevent race conditions by ensuring only one lens switch at a time
        guard !isConfiguring else {
            print("📸 Already configuring camera, ignoring lens switch request")
            return
        }
        
        // Don't do anything if we're already using this lens type or if we can't switch
        if lensType == currentLensType || cameraPosition == .front && lensType == .ultraWide {
            return
        }
        
        // Ultra-wide camera is only available on the back camera
        if cameraPosition == .front && lensType == .ultraWide {
            print("📸 Cannot use ultra-wide with front camera")
            return
        }
        
        isConfiguring = true
        
        print("📸 Switching lens type to: \(lensType)")
        
        // Update the lens type state on the main thread
        DispatchQueue.main.async {
            self.currentLensType = lensType
        }
        
        // Check if we need to reconfigure the camera session
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            // Capture the current device's white balance settings before switching
            var previousWhiteBalanceGains: AVCaptureDevice.WhiteBalanceGains?
            var previousWhiteBalanceMode: AVCaptureDevice.WhiteBalanceMode = .continuousAutoWhiteBalance
            
            // Get white balance settings from current device before switching
            if let oldDevice = self.currentDevice {
                // Save the current white balance settings if possible
                do {
                    try oldDevice.lockForConfiguration()
                    
                    // Save current white balance mode
                    previousWhiteBalanceMode = oldDevice.whiteBalanceMode
                    
                    // Get current white balance gains for smooth transition
                    previousWhiteBalanceGains = oldDevice.deviceWhiteBalanceGains
                    print("📸 Captured white balance from previous device: R:\(previousWhiteBalanceGains?.redGain ?? 0), G:\(previousWhiteBalanceGains?.greenGain ?? 0), B:\(previousWhiteBalanceGains?.blueGain ?? 0)")
                    
                    oldDevice.unlockForConfiguration()
                } catch {
                    print("📸 Could not capture white balance from previous device: \(error.localizedDescription)")
                }
            }
            
            // We need to stop the session while making changes
            self.session.beginConfiguration()
            
            // Remove observer for subject area change from old device
            if let oldDevice = self.currentDevice {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldDevice)
            }
            
            // Remove existing input
            if let inputs = self.session.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    self.session.removeInput(input)
                }
            }
            
            do {
                // Get the appropriate camera device based on lens type
                var device: AVCaptureDevice?
                switch lensType {
                case .ultraWide:
                    device = self.ultraWideDevice
                case .wideAngle:
                    device = self.wideAngleDevice
                }
                
                // Handle missing device - can't use guard with reassignment
                if device == nil {
                    print("📸 Failed to get camera device for lens type: \(lensType)")
                    
                    // Fall back to wide angle if ultra-wide is not available
                    if lensType == .ultraWide && self.wideAngleDevice != nil {
                        print("📸 Falling back to wide-angle camera")
                        self.currentLensType = .wideAngle
                        device = self.wideAngleDevice
                    } else {
                        // No fallback available
                        self.session.commitConfiguration()
                        return
                    }
                }
                
                // At this point, device should be non-nil, but double-check
                guard let device = device else {
                    print("📸 No camera device available")
                    self.session.commitConfiguration()
                    return
                }
                
                // Set initial zoom factor based on lens type
                let initialZoomFactor: CGFloat = (lensType == .ultraWide) ? 1.0 : 1.0
                
                // Store the device reference for zoom functionality
                self.currentDevice = device
                
                // Configure device for optimal settings
                try device.lockForConfiguration()
                
                // Set initial zoom factor
                device.videoZoomFactor = initialZoomFactor
                
                // Update the user-facing zoom factor
                if lensType == .ultraWide {
                    DispatchQueue.main.async {
                        self.zoomFactor = 0.5 // Show as 0.5x for ultra-wide
                    }
                } else {
                    DispatchQueue.main.async {
                        self.zoomFactor = 1.0 // Show as 1.0x for wide-angle
                    }
                }
                
                // Configure focus modes
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    device.isSmoothAutoFocusEnabled = true
                    
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .none
                    }
                }
                
                // Configure exposure mode
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    
                    // Use a faster shutter speed (1/500 sec) for sharper images
                    let fastShutter = CMTime(value: 1, timescale: 500) // 1/500 sec
                    // Set ISO to a reasonable value (or max if needed)
                    let iso = min(device.activeFormat.maxISO, 400)
                    
                    // Only set custom exposure if we're in good lighting conditions
                    if device.exposureDuration.seconds < 0.1 { // Current exposure is faster than 1/10s
                        print("📸 Setting shutter-priority exposure: 1/500s, ISO: \(iso)")
                        device.setExposureModeCustom(duration: fastShutter, iso: iso) { _ in
                            // After setting custom exposure, lock it to prevent auto changes
                            try? device.lockForConfiguration()
                            device.exposureMode = .locked
                            device.unlockForConfiguration()
                        }
                    }
                }
                
                // Apply previous white balance settings if available for smooth transition
                if let previousGains = previousWhiteBalanceGains,
                   device.isWhiteBalanceModeSupported(.locked) {
//                     Normalize the gains to ensure they're within the allowed range for this device
//                     BILL DEBUG TODO
                    let normalizedGains = self.normalizeGains(previousGains, for: device)
                    
                    //print("📸 Applying previous white balance to new device: R:\(normalizedGains.redGain), G:\(normalizedGains.greenGain), B:\(normalizedGains.blueGain), Mode: \(previousWhiteBalanceMode)")
                    
                    // Apply smooth white balance transition based on previous mode
                    if previousWhiteBalanceMode == .locked {
                        // Previous device had locked white balance, maintain it smoothly
                        // BILL DEBUG TODO
//                        device.setWhiteBalanceModeLocked(with: normalizedGains) { _ in
//                            print("📸 Maintained locked white balance from previous device")
//                        }
                    } else {
                        // Previous device was in auto mode, do a smooth transition
                        // Briefly apply the previous gains, then return to auto mode
                        device.setWhiteBalanceModeLocked(with: normalizedGains) { _ in
                            // Return to the previous mode after a short smooth transition
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                do {
                                    try device.lockForConfiguration()
                                    if device.isWhiteBalanceModeSupported(previousWhiteBalanceMode) {
                                        // BILL DEBUG TODO
                                        //device.whiteBalanceMode = previousWhiteBalanceMode
                                        print("📸 Restored previous white balance mode: \(previousWhiteBalanceMode)")
                                    } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                                        print("📸 Fallback to continuous auto white balance")
                                    }
                                    device.unlockForConfiguration()
                                } catch {
                                    print("📸 Error restoring white balance mode: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                } else {
                    // If no previous settings, use the previous mode or default to auto
                    if device.isWhiteBalanceModeSupported(previousWhiteBalanceMode) {
                        device.whiteBalanceMode = previousWhiteBalanceMode
                        print("📸 Using previous white balance mode: \(previousWhiteBalanceMode)")
                    } else if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                        print("📸 Using default continuous auto white balance")
                    }
                }
                
                // Enable subject area change monitoring
                device.isSubjectAreaChangeMonitoringEnabled = true
                print("📸 Enabled subject area change monitoring for \(lensType) camera")
                
                device.unlockForConfiguration()
                
                // Create and add new input
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    print("📸 Added new camera input for lens type: \(lensType)")
                } else {
                    print("📸 Could not add camera input for lens type: \(lensType)")
                }
                
                // Apply all configuration changes
                self.session.commitConfiguration()
                
                // Set up subject area change monitoring for new device
                self.setupSubjectAreaChangeMonitoring(for: device)
                
                self.configurePhotoOutputForMaxQuality()
                self.prepareZeroShutterLagCapture()
                
                // Now we can safely restart the session if it was running before
                if !self.session.isRunning {
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.session.startRunning()
                    }
                }
                
                // Reset configuration flag
                self.isConfiguring = false
            } catch {
                print("📸 Error switching lens type: \(error.localizedDescription)")
                self.session.commitConfiguration()
                // Reset configuration flag on error
                self.isConfiguring = false
            }
        }
    }
    
    // Method to switch between front and back cameras
    func switchCamera(to position: AVCaptureDevice.Position) {
        // Prevent race conditions by ensuring only one camera switch at a time
        guard !isConfiguring else {
            print("📸 Already configuring camera, ignoring camera switch request")
            return
        }
        
        // Don't do anything if we're already using this camera position
        if position == cameraPosition && currentDevice != nil {
            print("📸 Already using camera position: \(position)")
            return
        }
        
        isConfiguring = true
        
        print("📸 Switching camera to position: \(position)")
        
        // Update the camera position state on main thread
        DispatchQueue.main.async {
            self.cameraPosition = position
        }
        
        // Get a local copy of the lens type to avoid UI updates from a background thread
        let currentLensTypeSnapshot = currentLensType
        
        // Reset to wide-angle when switching to front camera since front doesn't support ultra-wide
        if position == .front && currentLensTypeSnapshot == .ultraWide {
            // Update the published property on main thread
            DispatchQueue.main.async {
                self.currentLensType = .wideAngle
            }
        }
        
        // Check if we need to reconfigure the camera session
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
            // Capture the current device's white balance settings before switching
            var previousWhiteBalanceGains: AVCaptureDevice.WhiteBalanceGains?
            
            // Get white balance settings from current device before switching
            if let oldDevice = self.currentDevice {
                // Save the current white balance settings if possible
                do {
                    try oldDevice.lockForConfiguration()
                    
                    // Get current white balance gains for potential transition
                    // Note: For front/back switches we usually don't want to preserve white balance
                    // as lighting conditions are often very different, but we'll capture just in case
                    previousWhiteBalanceGains = oldDevice.deviceWhiteBalanceGains
                    print("📸 Captured white balance from previous device: R:\(previousWhiteBalanceGains?.redGain ?? 0), G:\(previousWhiteBalanceGains?.greenGain ?? 0), B:\(previousWhiteBalanceGains?.blueGain ?? 0)")
                    
                    oldDevice.unlockForConfiguration()
                } catch {
                    print("📸 Could not capture white balance from previous device: \(error.localizedDescription)")
                }
            }
            
            // We need to stop the session while making changes
            self.session.beginConfiguration()
            
            // Remove observer for subject area change from old device
            if let oldDevice = self.currentDevice {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: oldDevice)
            }
            
            // Remove existing input
            if let inputs = self.session.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    self.session.removeInput(input)
                }
            }
            
            do {
                // Update available camera devices for new position
                self.wideAngleDevice = self.wideAngleCamera(position: position)
                
                if position == .back {
                    // Only look for ultra-wide on back camera
                    self.ultraWideDevice = self.ultraWideCamera()
                } else {
                    // Front camera doesn't have ultra-wide
                    self.ultraWideDevice = nil
                }
                
                // Get the appropriate device
                var device: AVCaptureDevice?
                if position == .back && currentLensType == .ultraWide && ultraWideDevice != nil {
                    device = ultraWideDevice
                } else {
                    device = wideAngleDevice
                    // Ensure we're using the correct lens type
                    if position == .front {
                        // Update the published property on main thread
                        DispatchQueue.main.async {
                            self.currentLensType = .wideAngle
                        }
                    }
                }
                
                guard let device = device else {
                    print("📸 Failed to get camera device for position: \(position)")
                    self.session.commitConfiguration()
                    return
                }
                
                // Store the device reference for zoom functionality
                self.currentDevice = device
                
                // Configure device settings
                try device.lockForConfiguration()
                
                // Set initial zoom factor
                device.videoZoomFactor = 1.0
                
                // Configure focus modes
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                    device.isSmoothAutoFocusEnabled = true
                    
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .none
                    }
                }
                
                // Configure exposure mode
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                    let fastShutter = CMTime(value: 1, timescale: 500) // 1/500 sec
                    // Set ISO to a reasonable value (or max if needed)
                    let iso = min(device.activeFormat.maxISO, 400)
                    
                    // Only set custom exposure if we're in good lighting conditions
                    if device.exposureDuration.seconds < 0.1 { // Current exposure is faster than 1/10s
                        print("📸 Setting shutter-priority exposure: 1/500s, ISO: \(iso)")
                        device.setExposureModeCustom(duration: fastShutter, iso: iso) { _ in
                            // After setting custom exposure, lock it to prevent auto changes
                            try? device.lockForConfiguration()
                            device.exposureMode = .locked
                            device.unlockForConfiguration()
                        }
                    }
                }
                
                // For front/back camera switches, usually we want a clean white balance
                // rather than preserving the previous one, as lighting conditions are typically different
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    // First use auto white balance to let the camera set an initial value
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                    print("📸 Using continuous auto white balance for new camera position")
                    
                    // Optional: We could try to use the previous gains with a more dramatic
                    // interpolation/transition, but typically it's better to let auto WB handle this
                    // for front/back switches
                }
                
                // Enable subject area change monitoring
                device.isSubjectAreaChangeMonitoringEnabled = true
                print("📸 Enabled subject area change monitoring for \(position) camera")
                
                device.unlockForConfiguration()
                
                // Create and add new input
                let newInput = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    print("📸 Added new camera input for position: \(position)")
                } else {
                    print("📸 Could not add camera input for position: \(position)")
                }
                
                // Apply all configuration changes
                self.session.commitConfiguration()
                
                // Set up subject area change monitoring for new device
                self.setupSubjectAreaChangeMonitoring(for: device)
                
                self.configurePhotoOutputForMaxQuality()
                self.prepareZeroShutterLagCapture()
                
                // Update UI properties on main thread
                DispatchQueue.main.async {
                    self.zoomFactor = 1.0
                    print("📸 Camera switch complete to position: \(position)")
                }
                
                // Now we can safely restart the session if it was running before
                if !self.session.isRunning {
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.session.startRunning()
                    }
                }
                
                // Reset configuration flag
                self.isConfiguring = false
                
            } catch {
                print("📸 Error switching camera: \(error.localizedDescription)")
                self.session.commitConfiguration()
                // Reset configuration flag on error
                self.isConfiguring = false
            }
        }
    }

    // Show the visual focus indicator at the specified point in the UI
    private func showFocusIndicator(at devicePoint: CGPoint) {
        // Convert the device point (0-1) to view coordinates for the overlay
        let viewPoint = convertToViewCoordinates(devicePoint: devicePoint)

        // Log the coordinates for debugging
        print("🎯 Device point: \(devicePoint.x), \(devicePoint.y)")
        print("🎯 View point: \(viewPoint.x), \(viewPoint.y)")

        // Make sure we're updating UI on the main thread
        DispatchQueue.main.async {
            // Update focus point in UI coordinates
            self.focusIndicatorPoint = viewPoint

            // Show the indicator
            self.showingFocusIndicator = true

            // Hide the indicator after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                // Smoothly animate out
                withAnimation(.easeOut(duration: 0.3)) {
                    self.showingFocusIndicator = false
                }
            }
        }
    }

    // Convert normalized device coordinates (0-1) to view coordinates
    private func convertToViewCoordinates(devicePoint: CGPoint) -> CGPoint {
        // The device coordinates are in the range 0-1
        // We need to scale them to our view size

        // When the video is rotated 90 degrees clockwise (portrait mode):
        // - The devicePoint.x (0-1, left-right) becomes the y-axis in view (bottom-top)
        // - The devicePoint.y (0-1, top-bottom) becomes the x-axis in view (left-right)

        // First, log the incoming coordinates and view size for debugging
        print("📏 Converting device point \(devicePoint.x), \(devicePoint.y) to view size \(viewSize.width)x\(viewSize.height)")

        // For a 90-degree clockwise rotation (which we have):
        // - x = y * width  (device y → view x)
        // - y = (1-x) * height (inverted device x → view y)
        let viewX = devicePoint.y * viewSize.width
        let viewY = (1 - devicePoint.x) * viewSize.height

        let result = CGPoint(x: viewX, y: viewY)
        print("Converted to view coordinates: \(result.x), \(result.y)")

        return result
    }
}

// Extend CameraModel to handle photo capture delegate
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

        // Print EXIF data for debugging
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
            print("📸 Image metadata: \(metadata)")
            
            // Log orientation information
            if let tiffDict = metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any],
               let orientation = tiffDict[String(kCGImagePropertyTIFFOrientation)] as? Int {
                print("📸 TIFF Orientation: \(orientation)")
            }
            
            if let exifDict = metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
               let orientation = exifDict[String(kCGImagePropertyOrientation)] as? Int {
                print("📸 EXIF Orientation: \(orientation)")
            }
        }

        // Save the image data directly with orientation preserved
        savePhoto(imageData)

        // Update UI with the captured image - we want to show the image with its natural orientation
        if let image = UIImage(data: imageData) {
            print("📸 Captured image orientation: \(image.imageOrientation.rawValue)")
            
            // Keep the original orientation for preview
            DispatchQueue.main.async {
                self.recentImage = image
            }
        }
    }
    
    // Handle deferred photo processing
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCapturingDeferredPhotoProxy proxy: AVCaptureDeferredPhotoProxy?, error: Error?) {
        guard error == nil else {
            print("Error with deferred photo: \(error!.localizedDescription)")
            return
        }
        
        // Show an instant preview using the proxy's pixel buffer
        if let previewPixelBuffer = proxy?.previewPixelBuffer {
            print("📸 Received deferred photo proxy with preview")
            
            // Convert the pixel buffer to a UIImage
            let ciImage = CIImage(cvPixelBuffer: previewPixelBuffer)
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let previewImage = UIImage(cgImage: cgImage)
                
                // Update the UI with this preview immediately
                DispatchQueue.main.async {
                    // We use the preview image as a temporary placeholder until the full quality image is ready
                    self.recentImage = previewImage
                }
            }
        } else {
            print("📸 Deferred photo proxy did not contain a preview")
        }
    }

    // Fix image orientation issues but preserve landscape vs portrait information in metadata
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // Store the original orientation for later reference
        _ = image.imageOrientation
        
        // Create image with correct orientation but preserve aspect ratio
        if image.imageOrientation == .up {
            return image
        }
        
        // Create a new image with correct orientation
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }

    private func savePhoto(_ imageData: Data) {
        // Processing metadata can be CPU intensive, do it on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Extract basic metadata if possible
            var metadata: [String: Any] = [:]

            if let source = CGImageSourceCreateWithData(imageData as CFData, nil) {
                if let imageMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                    metadata = imageMetadata
                    
                    // Get the EXIF orientation value
                    var exifOrientation: Int = 1 // Default to 1 (normal orientation)
                    
                    // First check EXIF dictionary
                    if let exifDict = metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
                       let orientation = exifDict[String(kCGImagePropertyOrientation)] as? Int {
                        exifOrientation = orientation
                        print("📸 Found EXIF orientation: \(orientation)")
                    }
                    // Then check TIFF dictionary
                    else if let tiffDict = metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any],
                            let orientation = tiffDict[String(kCGImagePropertyTIFFOrientation)] as? Int {
                        exifOrientation = orientation
                        print("📸 Found TIFF orientation: \(orientation)")
                    }
                    
                    // Store the original orientation value for later use
                    metadata["originalOrientation"] = exifOrientation
                    print("📸 Saved original orientation value: \(exifOrientation)")
                    
                    // Store the camera position that was used to take the photo
                    metadata["cameraPosition"] = self.cameraPosition == .front ? "front" : "back"
                    
                    // Check if this is a landscape photo by examining dimensions and orientation
                    if let pixelWidth = metadata[String(kCGImagePropertyPixelWidth)] as? Int,
                       let pixelHeight = metadata[String(kCGImagePropertyPixelHeight)] as? Int {
                        
                        // Determine if landscape based on both dimensions and orientation
                        // Orientation values 5-8 mean the image is rotated 90/270 degrees
                        let isRotated = (exifOrientation >= 5 && exifOrientation <= 8)
                        
                        // If rotated, swap dimensions for comparison
                        if isRotated {
                            metadata["isLandscape"] = pixelHeight > pixelWidth
                        } else {
                            metadata["isLandscape"] = pixelWidth > pixelHeight
                        }
                        
                        print("📸 Photo dimensions: \(pixelWidth)x\(pixelHeight), orientation: \(exifOrientation), isLandscape: \(metadata["isLandscape"] as? Bool ?? false), camera: \(metadata["cameraPosition"] as? String ?? "unknown")")
                    }
                    
                    // Preserve the original EXIF orientation
                    // DO NOT normalize the orientation here - we want to keep the original

                    // Add location data if enabled and available from LocationManager
                    // The FileManager will handle this now, no need to add it here
                }
            }

            // Save the photo with UTC timestamp filename
            do {
                let filename = try self.secureFileManager.savePhoto(imageData, withMetadata: metadata)
                print("Photo saved successfully with timestamp filename: \(filename)")
            } catch {
                print("Error saving photo: \(error.localizedDescription)")
            }
        }
    }
}

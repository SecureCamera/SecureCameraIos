//
//  ContentView.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/2/25.
//

import AVFoundation
import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject private var pinManager = PINManager.shared
    @ObservedObject private var appStateCoordinator = AppStateCoordinator.shared
    @State private var isShowingSettings = false
    @State private var isShowingGallery = false
    @State private var isAuthenticated = false
    @State private var isPINSetupComplete = false
    @State private var isShutterAnimating = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
    
    // Track device orientation changes
    @State private var deviceOrientation = UIDevice.current.orientation

    var body: some View {
        ZStack {
            if !pinManager.isPINSet {
                // First time setup - show PIN setup screen
                PINSetupView(isPINSetupComplete: $isPINSetupComplete)
            } else if !isAuthenticated || appStateCoordinator.needsAuthentication {
                // PIN verification screen
                PINVerificationView(isAuthenticated: $isAuthenticated)
                    .onChange(of: isAuthenticated) { _, authenticated in
                        if authenticated {
                            // Reset the coordinator's auth state when authenticated
                            appStateCoordinator.authenticationComplete()
                        }
                    }
            } else {
                // Camera view - now contains both the camera preview and focus indicator
                CameraView(cameraModel: cameraModel)
                    .edgesIgnoringSafeArea(.all)

                // Shutter animation overlay
                if isShutterAnimating {
                    Color.black
                        .opacity(0.8)
                        .edgesIgnoringSafeArea(.all)
                        .transition(.opacity)
                }

                // Camera controls overlay
                VStack {
                    // Top control bar with flash toggle and camera switch
                    HStack {
                        // Camera switch button
                        Button(action: {
                            toggleCameraPosition()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.top, 16)
                        .padding(.leading, 16)
                        
                        Spacer()

                        // Flash control button - disabled for front camera
                        Button(action: {
                            toggleFlashMode()
                        }) {
                            Image(systemName: flashIcon(for: cameraModel.flashMode))
                                .font(.system(size: 20))
                                .foregroundColor(cameraModel.cameraPosition == .front ? .gray : .white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .disabled(cameraModel.cameraPosition == .front)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }

                    Spacer()

                    // Zoom level indicator
                    ZStack {
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 80, height: 30)

                        Text(String(format: "%.1fx", cameraModel.zoomFactor))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    // Show for all zoom levels (including 0.5x for wide angle)
                    .opacity(cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
                    .animation(.easeInOut, value: cameraModel.zoomFactor)
                    .padding(.bottom, 10)
                    // Rotate the zoom indicator based on device orientation
                    .rotationEffect(getRotationAngle())
                    // Separate animation for rotation to ensure it responds to device orientation
                    // changes independent of zoom changes
                    .animation(.easeInOut, value: deviceOrientation)

                    HStack {
                        Button(action: {
                            isShowingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()

                        Spacer()

                        // Capture button
                        Button(action: {
                            triggerShutterEffect()
                            cameraModel.capturePhoto()
                        }) {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                                .background(Circle().fill(Color.white))
                                .padding()
                        }

                        Spacer()
                        Button(action: {
                            isShowingGallery = true
                        }) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    .padding(.bottom)
                }
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isShutterAnimating)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .obscuredWhenInactive()
                .screenCaptureProtected()
                .handleAppState(isPresented: $isShowingSettings)
                .withAuthenticationOverlay()
        }
        .sheet(isPresented: $isShowingGallery) {
            SecureGalleryView()
                .obscuredWhenInactive()
                .screenCaptureProtected()
                .handleAppState(isPresented: $isShowingGallery)
                .withAuthenticationOverlay()
        }
        // Apply privacy shield when app is inactive (task switcher, control center, etc.)
        .obscuredWhenInactive()
        // Protect against screen recording and screenshots
        .screenCaptureProtected()
        // Monitor PIN setup completion
        .onChange(of: isPINSetupComplete) { _, completed in
            if completed {
                print("PIN setup complete, authenticating user")
                isAuthenticated = true
                // Reset flag to avoid issues on subsequent launches
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isPINSetupComplete = false
                }
            }
        }
        .onAppear {
            print("ContentView appeared - PIN is set: \(pinManager.isPINSet), require PIN on resume: \(pinManager.requirePINOnResume)")
            
            // Check if PIN is set, and only auto-authenticate if PIN check is not required
            if pinManager.isPINSet {
                // Only auto-authenticate if PIN verification is not required
                isAuthenticated = !pinManager.requirePINOnResume
                print("PIN is set, auto-authentication set to: \(isAuthenticated)")
            } else {
                print("PIN is not set, showing PIN setup screen")
            }
            
            // Start monitoring orientation changes
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, 
                                                  object: nil, 
                                                  queue: .main) { _ in
                self.deviceOrientation = UIDevice.current.orientation
            }
        }
        .onDisappear {
            // Stop monitoring orientation changes
            NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        // Scene phase monitoring for background/foreground transitions
        .onChange(of: scenePhase) { _, newPhase in
            print("ContentView scene phase changed to: \(newPhase)")
            
            if newPhase == .active {
                // App is becoming active - let coordinator handle this
                appStateCoordinator.handleWillEnterForeground()
            } else if newPhase == .background {
                // App is going to background - let coordinator handle this
                appStateCoordinator.handleDidEnterBackground()
            } else if newPhase == .inactive {
                // Transitional state
                print("App becoming inactive")
            }
        }
        // Monitor authentication state from coordinator
        .onChange(of: appStateCoordinator.needsAuthentication) { _, needsAuth in
            if needsAuth {
                // Force re-authentication
                isAuthenticated = false
            }
        }
        // Monitor dismiss all sheets signal
        .onChange(of: appStateCoordinator.dismissAllSheets) { _, shouldDismiss in
            if shouldDismiss {
                // Dismiss all sheets
                isShowingSettings = false
                isShowingGallery = false
                
                // Reset flag after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appStateCoordinator.resetAuthenticationState()
                }
            }
        }
        // Camera permissions and setup are now handled in CameraModel's init method
        // This allows initialization to start immediately when the model is created
    }

    // Trigger the shutter animation effect
    private func triggerShutterEffect() {
        // Show the black overlay
        isShutterAnimating = true

        // Hide it after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isShutterAnimating = false
        }
    }

    // Toggle between flash modes (auto -> on -> off -> auto)
    private func toggleFlashMode() {
        switch cameraModel.flashMode {
        case .auto:
            cameraModel.flashMode = .on
        case .on:
            cameraModel.flashMode = .off
        case .off:
            cameraModel.flashMode = .auto
        @unknown default:
            cameraModel.flashMode = .auto
        }
    }
    
    // Toggle between front and back cameras
    private func toggleCameraPosition() {
        // Toggle between front and back cameras
        let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
        cameraModel.switchCamera(to: newPosition)
    }

    // Get the appropriate icon for the current flash mode
    private func flashIcon(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
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
    
    // Get rotation angle for the zoom indicator based on device orientation
    private func getRotationAngle() -> Angle {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return Angle(degrees: 90)
        case .landscapeRight:
            return Angle(degrees: -90)
        case .portraitUpsideDown:
            return Angle(degrees: 180)
        default:
            return Angle(degrees: 0) // Default to portrait
        }
    }
}

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
    @Published var minZoom: CGFloat = 0.5 // Allow going to 0.5x for ultra-wide
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
                print("📸 Enabled continuous auto-exposure")
                
                // For iOS 17+: Set shutter-priority exposure for sharper images
                if #available(iOS 17.0, *) {
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
                    } else {
                        print("📸 Low light detected, keeping auto exposure")
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
        // Check if fast capture prioritization is supported
        if output.isFastCapturePrioritizationSupported {
            print("Fast capture prioritization is supported, preparing zero shutter lag pipeline")
            let zslSettings = AVCapturePhotoSettings()
            output.setPreparedPhotoSettingsArray([zslSettings])
        } else {
            print("Fast capture prioritization is not supported on this device")
        }
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

        // Use AVCaptureDevice.RotationCoordinator for proper image rotation (iOS 17+ approach)
        let rotationCoordinator = AVCaptureDevice.RotationCoordinator(
            device: deviceInput.device, 
            previewLayer: preview // Use our preview layer for accurate coordination
        )
        
        // Set the rotation angle for proper horizon-level capture
        connection.videoRotationAngle = rotationCoordinator.videoRotationAngleForHorizonLevelCapture
        print("📸 Setting rotation angle from coordinator = \(connection.videoRotationAngle)°")
        
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
    
    // Switch between ultra-wide and wide-angle cameras
    func switchLensType(to lensType: CameraLensType) {
        // Don't do anything if we're already using this lens type or if we can't switch
        if lensType == currentLensType || cameraPosition == .front && lensType == .ultraWide {
            return
        }
        
        // Ultra-wide camera is only available on the back camera
        if cameraPosition == .front && lensType == .ultraWide {
            print("📸 Cannot use ultra-wide with front camera")
            return
        }
        
        print("📸 Switching lens type to: \(lensType)")
        
        // Update the lens type state on the main thread
        DispatchQueue.main.async {
            self.currentLensType = lensType
        }
        
        // Check if we need to reconfigure the camera session
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            
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
                    
                    // For iOS 17+: Set shutter-priority exposure for sharper images
                    if #available(iOS 17.0, *) {
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
                }
                
                // Configure white balance mode
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
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
                
                // If iOS 17+, prepare for zero shutter lag captures
                if #available(iOS 17.0, *) {
                    self.configurePhotoOutputForMaxQuality()
                    self.prepareZeroShutterLagCapture()
                }
                
                // Now we can safely restart the session if it was running before
                if !self.session.isRunning {
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.session.startRunning()
                    }
                }
            } catch {
                print("📸 Error switching lens type: \(error.localizedDescription)")
                self.session.commitConfiguration()
            }
        }
    }
    
    // Method to switch between front and back cameras
    func switchCamera(to position: AVCaptureDevice.Position) {
        // Don't do anything if we're already using this camera position
        if position == cameraPosition && currentDevice != nil {
            print("📸 Already using camera position: \(position)")
            return
        }
        
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
                    
                    // For iOS 17+: Set shutter-priority exposure for sharper images
                    if #available(iOS 17.0, *) {
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
                }
                
                // Configure white balance mode
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
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
                
                // If iOS 17+, prepare for zero shutter lag captures
                if #available(iOS 17.0, *) {
                    self.configurePhotoOutputForMaxQuality()
                    self.prepareZeroShutterLagCapture()
                }
                
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
                
            } catch {
                print("📸 Error switching camera: \(error.localizedDescription)")
                self.session.commitConfiguration()
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
    
    // Handle deferred photo processing (iOS 17+)
    @available(iOS 17.0, *)
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

// SwiftUI wrapper for the camera preview
struct CameraView: View {
    @ObservedObject var cameraModel: CameraModel
    
    // Add a slightly darker background to emphasize the capture area
    let backgroundOpacity: Double = 0.2

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color to emphasize the capture area
                Color.black
                    .edgesIgnoringSafeArea(.all)
                
                // Camera preview represented by UIViewRepresentable
                CameraPreviewView(cameraModel: cameraModel, viewSize: geometry.size)
                    .edgesIgnoringSafeArea(.all)

                // Focus indicator overlay with proper coordinates
                if cameraModel.showingFocusIndicator, let point = cameraModel.focusIndicatorPoint {
                    FocusIndicatorView()
                        .position(x: point.x, y: point.y)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: cameraModel.showingFocusIndicator)
                }
            }
            .onAppear {
                print("📏 Camera view size: \(geometry.size.width)x\(geometry.size.height)")
            }
        }
    }
}

// Focus square indicator
struct FocusIndicatorView: View {
    // Animation state
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Outer square with animation
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: isAnimating ? 70 : 80, height: isAnimating ? 70 : 80)
                .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isAnimating)

            // Inner square
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 50, height: 50)

            // Center crosshair
            ZStack {
                // Horizontal line
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 20, height: 1)

                // Vertical line
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 1, height: 20)
            }
        }
        .shadow(color: Color.black.opacity(0.5), radius: 2, x: 1, y: 1)
        .onAppear {
            isAnimating = true
        }
    }
}

// UIViewRepresentable for camera preview
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraModel: CameraModel
    var viewSize: CGSize // Store the parent view's size for coordinate conversion
    
    // Standard photo aspect ratio is 4:3
    // This is the ratio of most iPhone photos in portrait mode (3:4 actually, as width:height)
    private let photoAspectRatio: CGFloat = 3.0 / 4.0 // width/height in portrait mode
    
    // Store the view reference to help with coordinate mapping
    class CameraPreviewHolder {
        weak var view: UIView?
        var previewLayer: AVCaptureVideoPreviewLayer?
        var previewContainer: UIView? // Container with correct aspect ratio
    }

    // Shared holder to maintain a reference to the view and preview layer
    private let viewHolder = CameraPreviewHolder()

    func makeUIView(context: Context) -> UIView {
        // Create a view with the exact size passed from parent
        let view = UIView(frame: CGRect(origin: .zero, size: viewSize))
        print("📐 Creating camera preview with size: \(viewSize.width)x\(viewSize.height)")

        // Store the view reference
        viewHolder.view = view
        
        // Calculate the container size to match photo aspect ratio
        let containerSize = calculatePreviewContainerSize(for: viewSize)
        let containerOrigin = CGPoint(
            x: (viewSize.width - containerSize.width) / 2,
            y: (viewSize.height - containerSize.height) / 2
        )
        
        // Create the container view with proper aspect ratio
        let containerView = UIView(frame: CGRect(origin: containerOrigin, size: containerSize))
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = true
        view.addSubview(containerView)
        viewHolder.previewContainer = containerView
        
        // Add visual guides for the capture area
        
        // 1. Add a border to visualize the capture area
        let borderLayer = CALayer()
        borderLayer.frame = containerView.bounds
        borderLayer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        borderLayer.borderWidth = 2.0
        containerView.layer.addSublayer(borderLayer)
        
        // 2. Add corner brackets for a more camera-like appearance
        let cornerSize: CGFloat = 20.0
        let cornerThickness: CGFloat = 3.0
        let cornerColor = UIColor.white.withAlphaComponent(0.8).cgColor
        
        // Top-left corner
        let topLeftCornerH = CALayer()
        topLeftCornerH.frame = CGRect(x: 0, y: 0, width: cornerSize, height: cornerThickness)
        topLeftCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(topLeftCornerH)
        
        let topLeftCornerV = CALayer()
        topLeftCornerV.frame = CGRect(x: 0, y: 0, width: cornerThickness, height: cornerSize)
        topLeftCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(topLeftCornerV)
        
        // Top-right corner
        let topRightCornerH = CALayer()
        topRightCornerH.frame = CGRect(x: containerSize.width - cornerSize, y: 0, width: cornerSize, height: cornerThickness)
        topRightCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(topRightCornerH)
        
        let topRightCornerV = CALayer()
        topRightCornerV.frame = CGRect(x: containerSize.width - cornerThickness, y: 0, width: cornerThickness, height: cornerSize)
        topRightCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(topRightCornerV)
        
        // Bottom-left corner
        let bottomLeftCornerH = CALayer()
        bottomLeftCornerH.frame = CGRect(x: 0, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
        bottomLeftCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomLeftCornerH)
        
        let bottomLeftCornerV = CALayer()
        bottomLeftCornerV.frame = CGRect(x: 0, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
        bottomLeftCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomLeftCornerV)
        
        // Bottom-right corner
        let bottomRightCornerH = CALayer()
        bottomRightCornerH.frame = CGRect(x: containerSize.width - cornerSize, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
        bottomRightCornerH.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomRightCornerH)
        
        let bottomRightCornerV = CALayer()
        bottomRightCornerV.frame = CGRect(x: containerSize.width - cornerThickness, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
        bottomRightCornerV.backgroundColor = cornerColor
        containerView.layer.addSublayer(bottomRightCornerV)
        
        // Add a label to indicate that this is the capture area
        let captureLabel = UILabel()
        captureLabel.text = "CAPTURE AREA"
        captureLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        captureLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        captureLabel.sizeToFit()
        captureLabel.frame = CGRect(
            x: (containerSize.width - captureLabel.frame.width) / 2,
            y: 10,
            width: captureLabel.frame.width,
            height: captureLabel.frame.height
        )
        containerView.addSubview(captureLabel)
        
        // Create and configure the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.session = cameraModel.session
        previewLayer.frame = containerView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoRotationAngle = 90 // Force portrait orientation

        // Store the preview layer in our holder instead of directly in the cameraModel
        viewHolder.previewLayer = previewLayer

        // Ensure the layer is added to the container view
        containerView.layer.addSublayer(previewLayer)

        // Add gesture recognizers
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)

        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleDoubleTapGesture(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)

        // Add single tap gesture for quick focus
        let singleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleSingleTapGesture(_:)))
        singleTapGesture.requiresExclusiveTouchType = true

        // Ensure single tap doesn't conflict with double tap
        singleTapGesture.require(toFail: doubleTapGesture)
        view.addGestureRecognizer(singleTapGesture)

        // Note: We DO NOT start the session here anymore - it's handled below after configuration is committed

        // Store exact view dimensions in the model for coordinate mapping
        cameraModel.viewSize = viewSize

        // Assign the preview layer to cameraModel after the view is created
        // This needs to be done on the main thread since it modifies @Published property
        DispatchQueue.main.async {
            cameraModel.preview = previewLayer
        }

        return view
    }

    // Calculate the container size based on the photo aspect ratio
    private func calculatePreviewContainerSize(for size: CGSize) -> CGSize {
        // Calculate the container size to match photo aspect ratio
        // In portrait mode, we're comparing width:height
        // We prioritize fitting the width to match the device's screen width
        let width = size.width
        let height = width / photoAspectRatio
        
        // If height exceeds the available space, adjust both dimensions
        if height > size.height {
            // Use the available height
            let adjustedHeight = size.height
            let adjustedWidth = adjustedHeight * photoAspectRatio
            return CGSize(width: adjustedWidth, height: adjustedHeight)
        } else {
            return CGSize(width: width, height: height)
        }
    }
    
    func updateUIView(_ uiView: UIView, context _: Context) {
        // Update the preview layer frame when the view updates
        DispatchQueue.main.async {
            // Update frame with the latest size
            uiView.frame = CGRect(origin: .zero, size: viewSize)
            
            // Calculate the container size to match photo aspect ratio
            let containerSize = calculatePreviewContainerSize(for: viewSize)
            let containerOrigin = CGPoint(
                x: (viewSize.width - containerSize.width) / 2,
                y: (viewSize.height - containerSize.height) / 2
            )
            
            // Update the container view frame
            if let containerView = viewHolder.previewContainer {
                containerView.frame = CGRect(origin: containerOrigin, size: containerSize)
                
                // Update the preview layer frame to match container
                if let layer = viewHolder.previewLayer {
                    layer.frame = containerView.bounds
                    
                    // Ensure we're using the correct layer in the camera model
                    // Only update if necessary to avoid excessive property changes
                    if cameraModel.preview !== layer {
                        cameraModel.preview = layer
                    }
                }
                
                // Update all visual indicators
                if containerView.layer.sublayers?.count ?? 0 > 0 {
                    // Update border
                    if let borderLayer = containerView.layer.sublayers?.first(where: { $0.borderWidth > 0 }) {
                        borderLayer.frame = containerView.bounds
                    }
                    
                    // Update corner guides
                    let cornerSize: CGFloat = 20.0
                    let cornerThickness: CGFloat = 3.0
                    
                    // Find corner guides by their size and position
                    for layer in containerView.layer.sublayers ?? [] {
                        // Skip the border layer
                        if layer.borderWidth > 0 { continue }
                        
                        // Update corner layers based on their position
                        if layer.frame.origin.x == 0 && layer.frame.origin.y == 0 {
                            // Top-left horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: 0, y: 0, width: cornerSize, height: cornerThickness)
                            }
                            // Top-left vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: 0, y: 0, width: cornerThickness, height: cornerSize)
                            }
                        }
                        else if layer.frame.origin.y == 0 && layer.frame.origin.x > 0 {
                            // Top-right horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerSize, y: 0, width: cornerSize, height: cornerThickness)
                            }
                            // Top-right vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerThickness, y: 0, width: cornerThickness, height: cornerSize)
                            }
                        }
                        else if layer.frame.origin.x == 0 && layer.frame.origin.y > 0 {
                            // Bottom-left horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: 0, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
                            }
                            // Bottom-left vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: 0, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
                            }
                        }
                        else if layer.frame.origin.x > 0 && layer.frame.origin.y > 0 {
                            // Bottom-right horizontal
                            if layer.frame.height == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerSize, y: containerSize.height - cornerThickness, width: cornerSize, height: cornerThickness)
                            }
                            // Bottom-right vertical
                            else if layer.frame.width == cornerThickness {
                                layer.frame = CGRect(x: containerSize.width - cornerThickness, y: containerSize.height - cornerSize, width: cornerThickness, height: cornerSize)
                            }
                        }
                    }
                    
                    // Update the capture area label position
                    for subview in containerView.subviews {
                        if let label = subview as? UILabel, label.text == "CAPTURE AREA" {
                            label.frame = CGRect(
                                x: (containerSize.width - label.frame.width) / 2,
                                y: 10,
                                width: label.frame.width,
                                height: label.frame.height
                            )
                        }
                    }
                }
            }

            // Update the size in the model
            cameraModel.viewSize = containerSize // Store the actual photo preview size
            print("📐 Updated camera preview to size: \(containerSize.width)x\(containerSize.height)")
        }
    }
    
    // This method is called once after makeUIView
    func makeCoordinator() -> Coordinator {
        // Create coordinator first - this shouldn't trigger camera operations
        let coordinator = Coordinator(self)
        
        // Capture cameraModel to avoid potential reference issues
        let capturedCameraModel = cameraModel
        
        // Give a slight delay before starting the camera session
        // This ensures all UI setup is complete and configuration has been committed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Start camera on background thread after delay
            DispatchQueue.global(qos: .userInitiated).async {
                if !capturedCameraModel.session.isRunning {
                    print("📸 Starting camera session from makeCoordinator after delay")
                    capturedCameraModel.session.startRunning()
                }
            }
        }
        
        return coordinator
    }

    // Coordinator for handling UIKit gestures
    class Coordinator: NSObject {
        var parent: CameraPreviewView
        private var initialScale: CGFloat = 1.0

        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }

        // Handle pinch gesture for zoom with continuous updates
        @objc func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                // Store initial scale when gesture begins
                initialScale = gesture.scale
                parent.cameraModel.handlePinchGesture(scale: gesture.scale, initialScale: initialScale)

            case .changed:
                // Apply continuous updates for smoother zooming experience
                // The continuous timer helps ensure smoother transitions
                parent.cameraModel.handlePinchGesture(scale: gesture.scale)

            case .ended, .cancelled, .failed:
                // Ensure final value is applied when gesture completes
                parent.cameraModel.handlePinchGesture(scale: gesture.scale)

            default:
                break
            }
        }

        // Handle double tap gesture for focus and white balance
        @objc func handleDoubleTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            print("👆 Double tap detected at \(location.x), \(location.y)")
            
            // Get the container view for proper coordinate conversion
            guard let containerView = parent.viewHolder.previewContainer else { return }
            
            // Check if the tap is within the container bounds
            let locationInContainer = view.convert(location, to: containerView)
            if !containerView.bounds.contains(locationInContainer) {
                print("👆 Tap outside of capture area, ignoring")
                return
            }

            // Convert touch point to camera coordinate
            if let layer = parent.viewHolder.previewLayer {
                // Convert the point from the container's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: locationInContainer)
                print("👆 Converted to camera coordinates: \(pointInPreviewLayer.x), \(pointInPreviewLayer.y)")

                // Lock both focus and white balance
                // We set locked=true to indicate we want to lock white balance too
                parent.cameraModel.adjustCameraSettings(at: pointInPreviewLayer, lockWhiteBalance: true)
            }
        }

        // Handle single tap gesture for quick focus
        @objc func handleSingleTapGesture(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            print("👆 Single tap detected at \(location.x), \(location.y)")
            
            // Get the container view for proper coordinate conversion
            guard let containerView = parent.viewHolder.previewContainer else { return }
            
            // Check if the tap is within the container bounds
            let locationInContainer = view.convert(location, to: containerView)
            if !containerView.bounds.contains(locationInContainer) {
                print("👆 Tap outside of capture area, ignoring")
                return
            }

            // Convert touch point to camera coordinate
            if let layer = parent.viewHolder.previewLayer {
                // Convert the point from the container's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: locationInContainer)
                print("👆 Converted to camera coordinates: \(pointInPreviewLayer.x), \(pointInPreviewLayer.y)")

                // Adjust focus and exposure but not white balance
                parent.cameraModel.adjustCameraSettings(at: pointInPreviewLayer, lockWhiteBalance: false)
            }
        }
    }
}

// Authentication view for the initial screen
struct AuthenticationView: View {
    @Binding var isAuthenticated: Bool
    @State private var pin = ""
//    private let authManager = AuthenticationManager()

    var body: some View {
        EmptyView()
//        VStack(spacing: 20) {
//            Image(systemName: "lock.shield")
//                .font(.system(size: 70))
//                .foregroundColor(.blue)
//                .padding(.bottom, 30)
//
//            Text("Secure Camera")
//                .font(.largeTitle)
//                .bold()
//
//            Text("Enter your device PIN to continue")
//                .foregroundColor(.secondary)
//
//            // Simulated PIN entry UI
//            // In a real app, we'd use the device authentication
//            SecureField("PIN", text: $pin)
//                .keyboardType(.numberPad)
//                .padding()
//                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
//                .padding(.horizontal, 50)
//
//            Button(action: {
//                // Authenticate with device PIN
//                authManager.authenticate(withMethod: .devicePIN) { success in
//                    if success {
//                        isAuthenticated = true
//                    } else {
//                        // Handle failed authentication
//                        pin = ""
//                    }
//                }
//            }) {
//                Text("Unlock")
//                    .foregroundColor(.white)
//                    .padding()
//                    .frame(width: 200)
//                    .background(Color.blue)
//                    .cornerRadius(10)
//            }
//            .padding(.top, 30)
//        }
//        .padding()
    }
}

// Settings view with sharing, location, and security sections

// Photo cell view for gallery items
struct PhotoCell: View {
    let photo: SecurePhoto
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    // Track whether this cell is visible in the viewport
    @State private var isVisible: Bool = false
    
    // Cell size
    private let cellSize: CGFloat = 100

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Background for photos (shows black for landscape photos)
            Rectangle()
                .fill(Color.black)
                .frame(width: cellSize, height: cellSize)
                .cornerRadius(10)
            
            // Photo image with proper aspect ratio and orientation
            Image(uiImage: photo.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit) // Use .fit to preserve aspect ratio
                .frame(
                    width: photo.frameSizeForDisplay(cellSize: cellSize).width,
                    height: photo.frameSizeForDisplay(cellSize: cellSize).height
                )
                .frame(width: cellSize, height: cellSize) // Outer frame maintains cell size
                .cornerRadius(10)
                .onTapGesture(perform: onTap)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                // Track appearance/disappearance for memory management
                .onAppear {
                    // This cell is now visible
                    isVisible = true
                    photo.isVisible = true
                    MemoryManager.shared.reportThumbnailLoaded()
                }
                .onDisappear {
                    // This cell is no longer visible
                    isVisible = false
                    photo.markAsInvisible()
                    // Let the memory manager know it can clean up if needed
                    MemoryManager.shared.checkMemoryUsage()
                }

            // Selection checkmark when in selection mode and selected
            if isSelecting && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
                    .background(Circle().fill(Color.white))
                    .padding(5)
            }
        }
    }
}

// Extension to get rotation angle for a device orientation
// This replaces the deprecated AVCaptureVideoOrientation methods with iOS 17+ compliant alternatives
extension UIDeviceOrientation {
    func getRotationAngle() -> Double {
        switch self {
        case .portrait:
            return 90    // device upright → rotate 90° CW
        case .portraitUpsideDown:
            return 270   // device upside down → rotate 270° CW
        case .landscapeLeft:
            return 0     // device rotated left (home button right) → 0° rotation (natural)
        case .landscapeRight:
            return 180   // device rotated right (home button left) → 180° rotation
        default:
            return 90    // Default to portrait rotation if unknown
        }
    }
}

// Extension for UIImage to get an image with the correct orientation applied
extension UIImage {
    func imageWithProperOrientation() -> UIImage {
        // If already in correct orientation, return self
        if self.imageOrientation == .up {
            return self
        }
        
        // Create a proper oriented image
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }
}

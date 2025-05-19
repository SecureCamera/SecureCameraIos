//
//  ContentView.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/2/25.
//


import PhotosUI
import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var isShowingSettings = false
    @State private var isShowingGallery = false
    @State private var isAuthenticated = true // TODO, default
    @State private var isShutterAnimating = false

    var body: some View {
        ZStack {
            if !isAuthenticated {
                // Authentication screen
                AuthenticationView(isAuthenticated: $isAuthenticated)
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
                    // Top control bar with flash toggle
                    HStack {
                        Spacer()
                        
                        // Flash control button
                        Button(action: {
                            toggleFlashMode()
                        }) {
                            Image(systemName: flashIcon(for: cameraModel.flashMode))
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
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
                    .opacity(cameraModel.zoomFactor > 1.0 ? 1.0 : 0.0)
                    .animation(.easeInOut, value: cameraModel.zoomFactor)
                    .padding(.bottom, 10)

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
        }
        .sheet(isPresented: $isShowingGallery) {
            SecureGalleryView()
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
    @Published var minZoom: CGFloat = 1.0
    @Published var maxZoom: CGFloat = 10.0
    private var initialZoom: CGFloat = 1.0
    private var currentDevice: AVCaptureDevice?
    
    // View size for coordinate mapping
    var viewSize: CGSize = .zero
    
    // Focus indicator properties
    @Published var focusIndicatorPoint: CGPoint? = nil
    @Published var showingFocusIndicator = false
    
    // Flash control
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    
    // Timer to reset to auto-focus mode after tap-to-focus
    private var focusResetTimer: Timer?

    // Storage managers
    private let secureFileManager = SecureFileManager()

    // Initialize as part of class creation for faster startup
    override init() {
        super.init()
        // Begin checking permissions immediately when instance is created
        DispatchQueue.global(qos: .userInitiated).async {
            self.checkPermissions()
        }
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Update @Published property on main thread
            DispatchQueue.main.async {
                self.isPermissionGranted = true
            }
            // Set up on a high-priority background thread
            DispatchQueue.global(qos: .userInteractive).async {
                self.setupCamera()
            }
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { status in
                if status {
                    // Update @Published property on main thread
                    DispatchQueue.main.async {
                        self.isPermissionGranted = true
                    }
                    // Setup on a high-priority background thread immediately after permission is granted
                    DispatchQueue.global(qos: .userInteractive).async {
                        self.setupCamera()
                    }
                } else {
                    // If permission denied, update UI on main thread
                    DispatchQueue.main.async {
                        self.isPermissionGranted = false
                        self.alert = true
                    }
                }
            }
        default:
            // Update @Published properties on main thread
            DispatchQueue.main.async {
                self.isPermissionGranted = false
                self.alert = true
            }
        }
    }

    func setupCamera() {
        // Pre-configure an optimal camera session
        self.session.sessionPreset = .photo
        self.session.automaticallyConfiguresApplicationAudioSession = false

        do {
            self.session.beginConfiguration()

            // Add device input - use specific device type for faster initialization
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Failed to get camera device")
                return
            }

            // Store device reference for zoom functionality
            self.currentDevice = device

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
            }
            
            // Enable continuous auto white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("📸 Enabled continuous auto white balance")
            }
            
            // Set minimum and maximum focus distance if available
//            if #available(iOS 15.0, *), device.isLockingFocusWithCustomLensPositionSupported {
                // These settings help with depth of field optimization
                //print("📸 Focus distance range: \(device.minimumFocusDistance) to \(device.maximumFocusDistance)")
//            }

            device.unlockForConfiguration()

            // Create and add input
            let input = try AVCaptureDeviceInput(device: device)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            // Add photo output with high-quality settings
            if self.session.canAddOutput(self.output) {
                // First add the output to the session
                self.session.addOutput(self.output)
                
                // Now that the output is connected to the session, configure it
                if #available(iOS 16.0, *) {
                    // Only try to set maxPhotoDimensions after the output is connected
                    // to the session, as required by the API
                    if let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.last {
                        print("Setting max photo dimensions to \(maxDimensions.width)x\(maxDimensions.height)")
                        self.output.maxPhotoDimensions = maxDimensions
                    }
                } else {
                    // Fall back to deprecated API for earlier iOS versions
                    self.output.isHighResolutionCaptureEnabled = true
                }
            }

            // Apply all configuration changes at once
            self.session.commitConfiguration()

            // Update all @Published properties on the main thread
            DispatchQueue.main.async {
                self.minZoom = minZoomValue
                self.maxZoom = maxZoomValue
                self.zoomFactor = defaultZoomValue
            }
            
            // Start a periodic task to check and adjust focus if needed
            self.startPeriodicFocusCheck()
            
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }
    
    // Timer for periodic auto-focus check
    private var focusCheckTimer: Timer?
    
    // Start a periodic check to ensure focus is optimized
    private func startPeriodicFocusCheck() {
        // Cancel any existing timer
        focusCheckTimer?.invalidate()
        
        // Create a new timer that runs every 3 seconds
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkAndOptimizeFocus()
        }
    }
    
    // Check focus conditions and optimize if needed
    private func checkAndOptimizeFocus() {
        guard let device = self.currentDevice else { return }
        
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

    func capturePhoto() {
        // Configure photo settings with flash mode
        let photoSettings = AVCapturePhotoSettings()
        
        // Apply flash mode setting if flash is available
        if self.output.supportedFlashModes.contains(AVCaptureDevice.FlashMode(rawValue: flashMode.rawValue)!) {
            photoSettings.flashMode = flashMode
            print("📸 Using flash mode: \(flashMode)")
        } else {
            print("📸 Flash not supported for requested mode: \(flashMode)")
        }

        self.output.capturePhoto(with: photoSettings, delegate: self)
    }

    // Method to handle zoom with smooth animation
    func zoom(factor: CGFloat) {
        guard let device = self.currentDevice else { return }

        do {
            try device.lockForConfiguration()

            // Calculate new zoom factor
            var newZoomFactor = factor

            // Limit zoom factor to device's range
            newZoomFactor = max(minZoom, min(newZoomFactor, maxZoom))

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

        // Apply the zoom with animation for smoothness
        zoom(factor: newZoomFactor)
    }

    // Method to handle white balance and focus adjustment at a specific point
    func adjustCameraSettings(at point: CGPoint, lockWhiteBalance: Bool = false) {
        guard let device = self.currentDevice else { return }

        // Log original coordinates
        print("🎯 Request to focus at device coordinates: \(point.x), \(point.y), lockWhiteBalance: \(lockWhiteBalance)")
        
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
        guard let device = self.currentDevice else { return }
        
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
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            print("Failed to get image data")
            return
        }

        // Save the image data directly
        savePhoto(imageData)

        // Update UI with the captured image
        if let image = UIImage(data: imageData) {
            // Fix orientation for preview
            let correctedImage = fixImageOrientation(image)

            DispatchQueue.main.async {
                self.recentImage = correctedImage
            }
        }
    }

    // Fix image orientation issues
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // If the orientation is already correct, return the image as is
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

                    // Ensure orientation is preserved correctly in metadata
                    // This is important for re-opening the image with correct orientation
                    if var tiffDict = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
                        tiffDict[kCGImagePropertyTIFFOrientation as String] = 1 // Force "up" orientation
                        metadata[kCGImagePropertyTIFFDictionary as String] = tiffDict
                    }
                }
            }

            // Save the photo without encryption for now
            do {
                let _ = try self.secureFileManager.savePhoto(imageData, withMetadata: metadata)
                print("Photo saved successfully")
            } catch {
                print("Error saving photo: \(error.localizedDescription)")
            }
        }
    }
}

// SwiftUI wrapper for the camera preview
struct CameraView: View {
    @ObservedObject var cameraModel: CameraModel
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
                
                // Debug rectangle to show view bounds
                // Uncomment this to debug coordinate spaces
                // Rectangle()
                //     .stroke(Color.green, lineWidth: 2)
                //     .opacity(0.5)
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
    
    // Store the view reference to help with coordinate mapping
    class CameraPreviewHolder {
        weak var view: UIView?
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
    
    // Shared holder to maintain a reference to the view and preview layer
    private let viewHolder = CameraPreviewHolder()

    func makeUIView(context: Context) -> UIView {
        // Create a view with the exact size passed from parent
        let view = UIView(frame: CGRect(origin: .zero, size: viewSize))
        print("📐 Creating camera preview with size: \(viewSize.width)x\(viewSize.height)")
        
        // Store the view reference
        viewHolder.view = view
        
        // Create and configure the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.session = cameraModel.session
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoRotationAngle = 90 // Force portrait orientation
        
        // Store the preview layer in our holder instead of directly in the cameraModel
        viewHolder.previewLayer = previewLayer

        // Ensure the layer is added to the view
        view.layer.addSublayer(previewLayer)
        
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

        // Start the session on a background thread with higher priority
        DispatchQueue.global(qos: .userInteractive).async {
            if !cameraModel.session.isRunning {
                cameraModel.session.startRunning()
            }
        }
        
        // Store exact view dimensions in the model for coordinate mapping
        cameraModel.viewSize = viewSize
        
        // Assign the preview layer to cameraModel after the view is created
        // This needs to be done on the main thread since it modifies @Published property
        DispatchQueue.main.async {
            cameraModel.preview = previewLayer
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the preview layer frame when the view updates
        DispatchQueue.main.async {
            // Update frame with the latest size
            uiView.frame = CGRect(origin: .zero, size: viewSize)
            
            // Update the preview layer frame
            if let layer = viewHolder.previewLayer {
                layer.frame = uiView.bounds
                
                // Ensure we're using the correct layer in the camera model
                // Only update if necessary to avoid excessive property changes
                if cameraModel.preview !== layer {
                    cameraModel.preview = layer
                }
            }
            
            // Update the size in the model
            cameraModel.viewSize = viewSize
            print("📐 Updated camera preview to size: \(viewSize.width)x\(viewSize.height)")

            // Ensure the camera is running
            if !cameraModel.session.isRunning {
                DispatchQueue.global(qos: .userInteractive).async {
                    cameraModel.session.startRunning()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
            
            // Convert touch point to camera coordinate
            if let layer = parent.viewHolder.previewLayer {
                // Convert the point from the view's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: location)
                print("👆 Converted to camera coordinates: \(pointInPreviewLayer.x), \(pointInPreviewLayer.y)")
                
                // We need to convert pointInPreviewLayer to focus indicator point
                // This is now handled in the CameraModel's adjustCameraSettings method
                
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
            
            // Convert touch point to camera coordinate
            if let layer = parent.viewHolder.previewLayer {
                // Convert the point from the view's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: location)
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Photo image
            Image(uiImage: photo.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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



// Class to represent a photo in the app with optimized memory usage
class SecurePhoto: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    var metadata: [String: Any]
    let fileURL: URL
    
    // Memory tracking
    var isVisible: Bool = false
    private var lastAccessTime: Date = Date()
    
    // Use lazy loading for images to reduce memory usage
    private var _thumbnail: UIImage?
    private var _fullImage: UIImage?
    
    // Computed property to check if this photo is marked as a decoy
    var isDecoy: Bool {
        return metadata["isDecoy"] as? Bool ?? false
    }
    
    // Function to mark/unmark as decoy
    func setDecoyStatus(_ isDecoy: Bool) {
        metadata["isDecoy"] = isDecoy
        
        // Save updated metadata back to disk
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let secureFileManager = SecureFileManager()
                let metadataURL = try secureFileManager.getSecureDirectory().appendingPathComponent("\(filename).metadata")
                let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [])
                try metadataData.write(to: metadataURL)
                print("Updated decoy status for photo: \(filename)")
            } catch {
                print("Error updating decoy status: \(error.localizedDescription)")
            }
        }
    }
    
    // Thumbnail is loaded on demand and cached
    var thumbnail: UIImage {
        // Update last access time
        lastAccessTime = Date()
        
        if let cachedThumbnail = _thumbnail {
            return cachedThumbnail
        }
        
        // Load thumbnail if needed
        do {
            // Mark this photo as actively being used
            isVisible = true
            
            if let thumb = try secureFileManager.loadPhotoThumbnail(from: fileURL) {
                _thumbnail = thumb
                return thumb
            }
        } catch {
            print("Error loading thumbnail: \(error)")
        }
        
        // Fallback to placeholder
        return UIImage(systemName: "photo") ?? UIImage()
    }
    
    // Full image is loaded on demand
    var fullImage: UIImage {
        // Update last access time
        lastAccessTime = Date()
        
        if let cachedFullImage = _fullImage {
            return cachedFullImage
        }
        
        // Load full image if needed
        do {
            // Mark this photo as actively being used
            isVisible = true
            
            let (data, _) = try secureFileManager.loadPhoto(filename: filename)
            if let img = UIImage(data: data) {
                _fullImage = img
                
                // When we load a full image, notify the memory manager
                MemoryManager.shared.reportFullImageLoaded()
                
                return img
            }
        } catch {
            print("Error loading full image: \(error)")
        }
        
        // Fallback to thumbnail
        return thumbnail
    }
    
    // Mark as no longer visible in the UI
    func markAsInvisible() {
        isVisible = false
    }
    
    // Get the time since this photo was last accessed
    var timeSinceLastAccess: TimeInterval {
        return Date().timeIntervalSince(lastAccessTime)
    }
    
    // Clear memory when no longer needed
    func clearMemory(keepThumbnail: Bool = true) {
        if _fullImage != nil {
            _fullImage = nil
            
            // Notify memory manager when we free a full image
            MemoryManager.shared.reportFullImageUnloaded()
        }
        
        if !keepThumbnail && _thumbnail != nil {
            _thumbnail = nil
            
            // Notify memory manager when we free a thumbnail
            MemoryManager.shared.reportThumbnailUnloaded()
        }
    }
    
    init(filename: String, metadata: [String: Any], fileURL: URL, preloadedThumbnail: UIImage? = nil) {
        self.filename = filename
        self.metadata = metadata
        self.fileURL = fileURL
        self._thumbnail = preloadedThumbnail
    }
    
    // Legacy initializer for compatibility
    convenience init(filename: String, thumbnail: UIImage, fullImage: UIImage, metadata: [String: Any]) {
        self.init(filename: filename, metadata: metadata, fileURL: URL(fileURLWithPath: ""))
        self._thumbnail = thumbnail
        self._fullImage = fullImage
    }

    // Implement Equatable
    static func == (lhs: SecurePhoto, rhs: SecurePhoto) -> Bool {
        // Compare by id and filename
        return lhs.id == rhs.id && lhs.filename == rhs.filename
    }
    
    // Shared file manager instance
    private let secureFileManager = SecureFileManager()
}

// Singleton memory manager to track and clean up photo memory usage
class MemoryManager {
    static let shared = MemoryManager()
    
    // Memory tracking counters
    private var loadedFullImages: Int = 0
    private var loadedThumbnails: Int = 0
    
    // Memory thresholds
    private let maxLoadedFullImages = 3  // Maximum number of full images to keep in memory
    private let maxLoadedThumbnails = 30 // Maximum number of thumbnails to keep in memory
    private let thumbnailCacheDuration: TimeInterval = 60.0 // Time in seconds to keep thumbnails in cache
    
    // Registry of photos to manage
    private var managedPhotos: [SecurePhoto] = []
    
    private init() {}
    
    // Register photos for memory management
    func registerPhotos(_ photos: [SecurePhoto]) {
        managedPhotos = photos
    }
    
    // Report when a full image is loaded
    func reportFullImageLoaded() {
        loadedFullImages += 1
        checkMemoryUsage()
    }
    
    // Report when a full image is unloaded
    func reportFullImageUnloaded() {
        loadedFullImages = max(0, loadedFullImages - 1)
    }
    
    // Report when a thumbnail is loaded
    func reportThumbnailLoaded() {
        loadedThumbnails += 1
        checkMemoryUsage()
    }
    
    // Report when a thumbnail is unloaded
    func reportThumbnailUnloaded() {
        loadedThumbnails = max(0, loadedThumbnails - 1)
    }
    
    // Check and clean up memory if needed
    func checkMemoryUsage() {
        // Clean up full images if over threshold
        if loadedFullImages > maxLoadedFullImages {
            cleanupFullImages()
        }
        
        // Clean up thumbnails if over threshold
        if loadedThumbnails > maxLoadedThumbnails {
            cleanupThumbnails()
        }
    }
    
    // Free memory for photos that are not visible
    private func cleanupFullImages() {
        let nonVisiblePhotos = managedPhotos.filter { !$0.isVisible }
        
        // Sort by last access time (oldest first)
        let sortedPhotos = nonVisiblePhotos.sorted { $0.timeSinceLastAccess > $1.timeSinceLastAccess }
        
        // Clear memory for the oldest photos
        for photo in sortedPhotos {
            photo.clearMemory(keepThumbnail: true)
            
            // Stop when we're below threshold
            if loadedFullImages <= maxLoadedFullImages {
                break
            }
        }
    }
    
    // Free memory for thumbnail images of photos that haven't been accessed recently
    private func cleanupThumbnails() {
        let nonVisiblePhotos = managedPhotos.filter { !$0.isVisible }
        
        // Find photos whose thumbnails haven't been accessed in a while
        let oldThumbnails = nonVisiblePhotos.filter { $0.timeSinceLastAccess > thumbnailCacheDuration }
        
        // Clear thumbnails for old photos
        for photo in oldThumbnails {
            photo.clearMemory(keepThumbnail: false)
            
            // Stop when we're below threshold
            if loadedThumbnails <= maxLoadedThumbnails {
                break
            }
        }
    }
    
    // Free all memory to reset state
    func freeAllMemory() {
        for photo in managedPhotos {
            photo.clearMemory(keepThumbnail: false)
        }
        
        loadedFullImages = 0
        loadedThumbnails = 0
    }
}



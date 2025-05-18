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
struct SettingsView: View {
    // Sharing options
    @State private var sanitizeFileName = true
    @State private var sanitizeMetadata = true
    
    // Privacy and detection options
    @AppStorage("showFaceDetection") private var showFaceDetection = true
    
    // Security settings
    @State private var biometricEnabled = false
    @State private var sessionTimeout = 5 // minutes
    @State private var appPIN = ""
    @State private var poisonPIN = ""
    @State private var showResetConfirmation = false
    
    // Location permissions
    @State private var locationPermissionStatus = "Not Determined"
    
    // Dependency injections (commented until implementations are ready)
    // private let authManager = AuthenticationManager()
    // private let locationManager = CLLocationManager()

    var body: some View {
        NavigationView {
            List {
                // SHARING SECTION
                Section(header: Text("Sharing Options")) {
                    Toggle("Sanitize File Name", isOn: $sanitizeFileName)
                        .onChange(of: sanitizeFileName) { _, newValue in
                            print("Sanitize file name: \(newValue)")
                            // TODO: Update user preferences
                        }
                    
                    Toggle("Sanitize Metadata", isOn: $sanitizeMetadata)
                        .onChange(of: sanitizeMetadata) { _, newValue in
                            print("Sanitize metadata: \(newValue)")
                            // TODO: Update user preferences
                        }
                        
                    Text("When enabled, personal information will be removed from photos before sharing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                // PRIVACY & DETECTION SECTION
                Section(header: Text("Privacy & Detection")) {
                    Toggle("Face Detection", isOn: $showFaceDetection)
                        .onChange(of: showFaceDetection) { _, newValue in
                            print("Face detection: \(newValue)")
                        }
                    
                    Text("When enabled, faces can be detected in photos for privacy protection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                // LOCATION SECTION
                Section(header: Text("Location")) {
                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(locationPermissionStatus)
                            .foregroundColor(locationStatusColor)
                    }
                    
                    Button("Check Location Permission") {
                        checkLocationPermission()
                    }
                    
                    Text("Location data can be embedded in photos when permission is granted")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                // SECURITY SECTION
                Section(header: Text("Security")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text("Secure")
                            .foregroundColor(.green)
                    }
                    
                    Picker("Session Timeout", selection: $sessionTimeout) {
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("Never").tag(0)
                    }
                    .onChange(of: sessionTimeout) { _, newValue in
                        print("Session timeout changed to \(newValue) minutes")
                        // TODO: Update user preferences
                    }
                    
                    Toggle("Biometric Authentication", isOn: $biometricEnabled)
                        .onChange(of: biometricEnabled) { _, newValue in
                            print("Biometric auth: \(newValue)")
                            // TODO: Update auth manager
                            // authManager.isBiometricEnabled = newValue
                        }
                }
                
                // APP PIN SECTION
                Section(header: Text("App PIN"), footer: Text("Set an app-specific PIN for additional security")) {
                    SecureField("Set App PIN", text: $appPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode) // Prevents keychain suggestions
                    
                    Button("Save App PIN") {
                        if !appPIN.isEmpty {
                            print("Setting app PIN")
                            // authManager.setAppPIN(appPIN)
                            appPIN = ""
                        }
                    }
                    .disabled(appPIN.isEmpty)
                }
                
                // EMERGENCY ERASURE SECTION (POISON PILL)
                Section(header: Text("Emergency Erasure"), footer: Text("If this PIN is entered, all photos will be immediately deleted")) {
                    SecureField("Set Emergency PIN", text: $poisonPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode) // Prevents keychain suggestions
                    
                    Button("Save Emergency PIN") {
                        if !poisonPIN.isEmpty {
                            print("Setting poison PIN")
                            // authManager.setPoisonPIN(poisonPIN)
                            poisonPIN = ""
                        }
                    }
                    .foregroundColor(.red)
                    .disabled(poisonPIN.isEmpty)
                }
                
                // SECURITY RESET SECTION
                Section {
                    Button("Reset All Security Settings") {
                        showResetConfirmation = true
                    }
                    .foregroundColor(.red)
                    
                } footer: {
                    Text("Resets all security settings to default values. Does not delete photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                checkLocationPermission()
            }
            .alert(isPresented: $showResetConfirmation) {
                Alert(
                    title: Text("Reset Security Settings"),
                    message: Text("Are you sure you want to reset all security settings to default? This action cannot be undone."),
                    primaryButton: .destructive(Text("Reset")) {
                        resetSecuritySettings()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var locationStatusColor: Color {
        switch locationPermissionStatus {
        case "Authorized":
            return .green
        case "Denied", "Restricted":
            return .red
        default:
            return .orange
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkLocationPermission() {
        // In a real implementation, this would use CLLocationManager
        // For now we'll simulate the permission check
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Simulate different permission states for demo purposes
            let statuses = ["Not Determined", "Authorized", "Denied", "Restricted"]
            self.locationPermissionStatus = statuses[Int.random(in: 0..<statuses.count)]
        }
    }
    
    private func resetSecuritySettings() {
        // Reset all security settings to default values
        biometricEnabled = false
        sessionTimeout = 5
        appPIN = ""
        poisonPIN = ""
        
        // In a real implementation:
        // authManager.resetSecuritySettings()
        print("Security settings have been reset")
    }
}

// Photo cell view for gallery items
struct PhotoCell: View {
    let photo: SecurePhoto
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

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

// Empty state view when no photos exist
struct EmptyGalleryView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Text("No photos yet")
                .font(.title)
                .foregroundColor(.secondary)

//            Button("Go Back and Take Photos", action: onDismiss)
//                .padding()
//                .background(Color.blue)
//                .foregroundColor(.white)
//                .cornerRadius(10)
//                .padding(.top, 20)
        }
    }
}

// Gallery toolbar view
struct GalleryToolbar: ToolbarContent {
    @Binding var isSelecting: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var selectedPhotoIds: Set<UUID>
    let hasSelection: Bool
    let onRefresh: () -> Void
    let onShare: () -> Void

    var body: some ToolbarContent {
        // Left side button (Select/Cancel)
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                if isSelecting {
                    // If we're currently selecting, cancel selection mode and clear selections
                    isSelecting = false
                    selectedPhotoIds.removeAll()
                } else {
                    // Enter selection mode
                    isSelecting = true
                }
            }) {
                Text(isSelecting ? "Cancel" : "Select")
                    .foregroundColor(isSelecting ? .red : .blue)
            }
        }

        // Right side buttons (delete/share when selecting, refresh/import otherwise)
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 20) {
                // When in selection mode and items are selected, show delete button
                if isSelecting && hasSelection {
                    // Delete button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    
                    // Share button
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                } 
                // When not in selection mode or nothing selected, show refresh button
                else if !isSelecting {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}

// Gallery view to display the stored photos
struct SecureGalleryView: View {
    @State private var photos: [SecurePhoto] = []
    @State private var selectedPhoto: SecurePhoto?
    @AppStorage("showFaceDetection") private var showFaceDetection = true  // Using AppStorage to share with Settings
    @State private var isSelecting: Bool = false
    @State private var selectedPhotoIds = Set<UUID>()
    @State private var showDeleteConfirmation = false
    @State private var isShowingImagePicker = false
    @State private var importedImage: UIImage?
    @State private var importedImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    
    private let secureFileManager = SecureFileManager()
    @Environment(\.dismiss) private var dismiss

    // Computed properties to simplify the view
    private var hasSelection: Bool {
        !selectedPhotoIds.isEmpty
    }
    
    // Get an array of selected photos for sharing
    private var selectedPhotos: [UIImage] {
        photos
            .filter { selectedPhotoIds.contains($0.id) }
            .map { $0.fullImage }
    }

    var body: some View {
//        VStack {
//        }
        NavigationView {
            Group {
                if photos.isEmpty {
                    EmptyGalleryView(onDismiss: { dismiss() })
                } else {
                    photosGridView
                }
            }
            .navigationTitle("Secure Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show import button when not in selection mode
                if !isSelecting {
                    // Import button
                    ToolbarItem(placement: .navigationBarTrailing) {
                        
                        PhotosPicker(selection: $pickerItems, matching: .images) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16))
                        }
                        .onChange(of: pickerItems) { _, _ in
                            Task {
                                for item in pickerItems {
                                    if let data = try? await item.loadTransferable(type: Data.self) {
                                        importedImages.append(UIImage(data: data)!)
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Gallery toolbar with selection mode
                GalleryToolbar(
                    isSelecting: $isSelecting,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    selectedPhotoIds: $selectedPhotoIds,
                    hasSelection: hasSelection,
                    onRefresh: loadPhotos,
                    onShare: shareSelectedPhotos
                )
            }
            .onAppear(perform: loadPhotos)
            .onChange(of: selectedPhoto) { _, newValue in
                if newValue == nil {
                    loadPhotos()
                }
            }
//            .sheet(isPresented: $isShowingImagePicker) {
//// old way
////                ImagePicker(image: $importedImage, onDismiss: handleImportedImage)
//                EmptyView()
//            }
            .sheet(item: $selectedPhoto) { photo in
                // Find the index of the selected photo in the photos array
                if let initialIndex = photos.firstIndex(where: { $0.id == photo.id }) {
                    PhotoDetailView(
                        allPhotos: photos,
                        initialIndex: initialIndex,
                        showFaceDetection: showFaceDetection,
                        onDelete: { _ in loadPhotos() }
                    )
                } else {
                    // Fallback if photo not found in array
                    PhotoDetailView(
                        photo: photo,
                        showFaceDetection: showFaceDetection,
                        onDelete: { _ in loadPhotos() }
                    )
                }
            }
            .alert(isPresented: $showDeleteConfirmation) {
                deleteConfirmationAlert
            }
        }
    }

    // Photo grid subview
    private var photosGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(photos) { photo in
                    PhotoCell(
                        photo: photo,
                        isSelected: selectedPhotoIds.contains(photo.id),
                        isSelecting: isSelecting,
                        onTap: {
                            handlePhotoTap(photo)
                        },
                        onDelete: {
                            prepareToDeleteSinglePhoto(photo)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // Delete confirmation alert
    private var deleteConfirmationAlert: Alert {
        Alert(
            title: Text("Delete Photo\(selectedPhotoIds.count > 1 ? "s" : "")"),
            message: Text("Are you sure you want to delete \(selectedPhotoIds.count) photo\(selectedPhotoIds.count > 1 ? "s" : "")? This action cannot be undone."),
            primaryButton: .destructive(Text("Delete"), action: deleteSelectedPhotos),
            secondaryButton: .cancel()
        )
    }
    
    // Handle imported image from picker
    private func handleImportedImage() {
        guard let image = importedImage else { return }
        
        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return
        }
        
        // Save imported photo
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create basic metadata
                let metadata: [String: Any] = [
                    "imported": true,
                    "creationDate": Date().timeIntervalSince1970
                ]
                
                let _ = try secureFileManager.savePhoto(imageData, withMetadata: metadata)
                print("Imported photo saved successfully")
                
                // Reload photos to show the new one
                DispatchQueue.main.async {
                    self.importedImage = nil
                    self.loadPhotos()
                }
            } catch {
                print("Error saving imported photo: \(error.localizedDescription)")
            }
        }
    }
//}

    // MARK: - Action methods

    private func handlePhotoTap(_ photo: SecurePhoto) {
        if isSelecting {
            togglePhotoSelection(photo)
        } else {
            selectedPhoto = photo
        }
    }

    private func togglePhotoSelection(_ photo: SecurePhoto) {
        if selectedPhotoIds.contains(photo.id) {
            selectedPhotoIds.remove(photo.id)
        } else {
            selectedPhotoIds.insert(photo.id)
        }
    }

    private func prepareToDeleteSinglePhoto(_ photo: SecurePhoto) {
        selectedPhotoIds = [photo.id]
        showDeleteConfirmation = true
    }

    // Utility function to fix image orientation
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        // If the orientation is already correct, return the image as is
        if image.imageOrientation == .up {
            return image
        }

        // Create a new CGContext with proper orientation
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return normalizedImage
    }

    private func loadPhotos() {
        // Load photos in the background thread to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let photoData = try self.secureFileManager.loadAllPhotos()

                // Convert loaded photos to SecurePhoto objects
                var loadedPhotos = photoData.map { (filename, data, metadata) in
                    // Create a full image from the data
                    if let image = UIImage(data: data) {
                        // Fix the orientation
                        let correctedImage = self.fixImageOrientation(image)

                        // Use the same image for thumbnail for simplicity
                        return SecurePhoto(
                            filename: filename,
                            thumbnail: correctedImage,
                            fullImage: correctedImage,
                            metadata: metadata
                        )
                    } else {
                        // Fallback to a placeholder if image can't be created
                        return SecurePhoto(
                            filename: filename,
                            thumbnail: UIImage(),
                            fullImage: UIImage(),
                            metadata: metadata
                        )
                    }
                }

                // Sort photos by creation date (oldest at top, newest at bottom)
                loadedPhotos.sort { photo1, photo2 in
                    // Get creation dates from metadata
                    let date1 = photo1.metadata["creationDate"] as? Double ?? 0
                    let date2 = photo2.metadata["creationDate"] as? Double ?? 0

                    // Sort by date (ascending - oldest first)
                    return date1 < date2
                }

                // Update UI on the main thread
                DispatchQueue.main.async {
                    self.photos = loadedPhotos
                }
            } catch {
                print("Error loading photos: \(error.localizedDescription)")
            }
        }
    }

    private func deletePhoto(_ photo: SecurePhoto) {
        // Perform file deletion in background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.secureFileManager.deletePhoto(filename: photo.filename)

                // Update UI on main thread
                DispatchQueue.main.async {
                    // Remove from the local array
                    withAnimation {
                        self.photos.removeAll { $0.id == photo.id }
                        if self.selectedPhotoIds.contains(photo.id) {
                            self.selectedPhotoIds.remove(photo.id)
                        }
                    }
                }
            } catch {
                print("Error deleting photo: \(error.localizedDescription)")
            }
        }
    }

    private func deleteSelectedPhotos() {
        // Create a local copy of the photos to delete
        let photosToDelete = selectedPhotoIds.compactMap { id in
            photos.first(where: { $0.id == id })
        }

        // Clear selection and exit selection mode immediately
        // for better UI responsiveness
        DispatchQueue.main.async {
            self.selectedPhotoIds.removeAll()
            self.isSelecting = false
        }

        // Process deletions in a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let group = DispatchGroup()

            // Delete each photo
            for photo in photosToDelete {
                group.enter()
                do {
                    try self.secureFileManager.deletePhoto(filename: photo.filename)
                    group.leave()
                } catch {
                    print("Error deleting photo: \(error.localizedDescription)")
                    group.leave()
                }
            }

            // After all deletions are complete, update the UI
            group.notify(queue: .main) {
                // Remove deleted photos from our array
                withAnimation {
                    self.photos.removeAll { photo in
                        photosToDelete.contains { $0.id == photo.id }
                    }
                }
            }
        }
    }
    
    // Share selected photos
    private func shareSelectedPhotos() {
        // Get all the selected photos
        let images = selectedPhotos
        
        guard !images.isEmpty else { return }
        
        // Use UIApplication.shared.windows approach for SwiftUI integration
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            print("Could not find root view controller")
            return
        }
        
        // Create a UIActivityViewController to show the sharing options
        let activityViewController = UIActivityViewController(
            activityItems: images,
            applicationActivities: nil
        )
        
        // For iPad support
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Find the presented view controller to present from
        var currentController = rootViewController
        while let presented = currentController.presentedViewController {
            currentController = presented
        }
        
        // Present the share sheet from the topmost presented controller
        DispatchQueue.main.async {
            currentController.present(activityViewController, animated: true, completion: nil)
        }
    }
}

// Struct to represent a photo in the app
struct SecurePhoto: Identifiable, Equatable {
    let id = UUID()
    let filename: String
    let thumbnail: UIImage
    let fullImage: UIImage
    let metadata: [String: Any]

    // Implement Equatable
    static func == (lhs: SecurePhoto, rhs: SecurePhoto) -> Bool {
        // Compare by id and filename
        return lhs.id == rhs.id && lhs.filename == rhs.filename
    }
}

// Photo detail view that supports swiping between photos
struct PhotoDetailView: View {
    // For single photo case (fallback)
    var photo: SecurePhoto? = nil
    
    // For multiple photos case
    @State private var allPhotos: [SecurePhoto] = []
    var initialIndex: Int = 0
    
    let showFaceDetection: Bool
    var onDelete: ((SecurePhoto) -> Void)? = nil
    
    @State private var currentIndex: Int = 0
    @State private var showDeleteConfirmation = false
    @State private var imageRotation: Double = 0
    @State private var offset: CGFloat = 0
    @State private var isSwiping: Bool = false
    
    // Face detection states
    @State private var isFaceDetectionActive = false
    @State private var detectedFaces: [DetectedFace] = []
    @State private var processingFaces = false
    @State private var modifiedImage: UIImage?
    @State private var showBlurConfirmation = false
    @State private var selectedMaskMode: MaskMode = .blur
    @State private var showMaskOptions = false
    
    // Image info states
    @State private var showImageInfo = false
    
    // Used to measure the displayed image size
    @State private var imageFrameSize: CGSize = .zero
    
    private let faceDetector = FaceDetector()
    @Environment(\.dismiss) private var dismiss
    private let secureFileManager = SecureFileManager()
    
    // Computed properties for mask action text
    private var maskActionTitle: String {
        switch selectedMaskMode {
        case .blur:
            return "Blur Selected Faces"
        case .pixelate:
            return "Pixelate Selected Faces"
        case .blackout:
            return "Blackout Selected Faces"
        case .noise:
            return "Apply Noise to Selected Faces"
        }
    }
    
    private var maskActionVerb: String {
        switch selectedMaskMode {
        case .blur:
            return "blur"
        case .pixelate:
            return "pixelate"
        case .blackout:
            return "blackout"
        case .noise:
            return "apply noise to"
        }
    }
    
    private var maskButtonLabel: String {
        switch selectedMaskMode {
        case .blur:
            return "Blur Faces"
        case .pixelate:
            return "Pixelate Faces"
        case .blackout:
            return "Blackout Faces"
        case .noise:
            return "Apply Noise"
        }
    }
    
    // Initialize the current index in init
    init(photo: SecurePhoto, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil) {
        self.photo = photo
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
    }
    
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil) {
        self._allPhotos = State(initialValue: allPhotos)
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
    }
    
    // Get the current photo to display
    private var currentPhoto: SecurePhoto {
        if !allPhotos.isEmpty {
            return allPhotos[currentIndex]
        } else if let photo = photo {
            return photo
        } else {
            // Should never happen but just in case
            return SecurePhoto(filename: "", thumbnail: UIImage(), fullImage: UIImage(), metadata: [:])
        }
    }
    
    // Get the image to display (original or modified)
    private var displayedImage: UIImage {
        if isFaceDetectionActive, let modified = modifiedImage {
            return modified
        } else {
            return currentPhoto.fullImage
        }
    }
    
    // Check if navigation is possible
    private var canGoToPrevious: Bool {
        !allPhotos.isEmpty && currentIndex > 0
    }
    
    private var canGoToNext: Bool {
        !allPhotos.isEmpty && currentIndex < allPhotos.count - 1
    }
    
    // Check if any faces are selected for blurring
    private var hasFacesSelected: Bool {
        detectedFaces.contains { $0.isSelected }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.opacity(0.05)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Photo counter at the top if we have multiple photos
                    if !allPhotos.isEmpty {
                        Text("\(currentIndex + 1) of \(allPhotos.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    
                    Spacer()
                    
                    // Centered image display
                    ZStack {
                        // Image display
                        Image(uiImage: displayedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(.degrees(imageRotation))
                            .offset(x: offset)
                            .overlay(
                                GeometryReader { imageGeometry in
                                    Color.clear
                                        .preference(key: SizePreferenceKey.self, value: imageGeometry.size)
                                        .onPreferenceChange(SizePreferenceKey.self) { size in
                                            self.imageFrameSize = size
                                        }
                                    
                                    // Face detection overlay
                                    if isFaceDetectionActive {
                                        ZStack {
                                            // Overlay each detected face with a red rectangle
                                            ForEach(detectedFaces) { face in
                                                let scaledRect = face.scaledRect(
                                                    originalSize: currentPhoto.fullImage.size,
                                                    displaySize: imageFrameSize
                                                )
                                                
                                                Rectangle()
                                                    .stroke(face.isSelected ? Color.green : Color.red, lineWidth: 3)
                                                    .frame(
                                                        width: scaledRect.width,
                                                        height: scaledRect.height
                                                    )
                                                    .position(
                                                        x: scaledRect.midX,
                                                        y: scaledRect.midY
                                                    )
                                                    .onTapGesture {
                                                        toggleFaceSelection(face)
                                                    }
                                            }
                                        }
                                    }
                                }
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        // Only enable horizontal swipes if we have multiple photos and face detection is inactive
                                        if !allPhotos.isEmpty && !isFaceDetectionActive {
                                            isSwiping = true
                                            offset = gesture.translation.width
                                        }
                                    }
                                    .onEnded { gesture in
                                        // Only process swipe if face detection is inactive
                                        if !isFaceDetectionActive {
                                            // Determine if the swipe is significant enough to change photos
                                            // Threshold is 1/4 of screen width
                                            let threshold: CGFloat = geometry.size.width / 4
                                            
                                            if offset > threshold && canGoToPrevious {
                                                navigateToPrevious()
                                            } else if offset < -threshold && canGoToNext {
                                                navigateToNext()
                                            }
                                            
                                            // Reset the offset with animation
                                            withAnimation {
                                                offset = 0
                                                isSwiping = false
                                            }
                                        }
                                    }
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.7)
                    
                    Spacer()
                    
                    // Processing indicator
                    if processingFaces {
                        ProgressView("Detecting faces...")
                            .padding()
                    }
                    
                    // Face detection controls - only shown when in face detection mode
                    if isFaceDetectionActive {
                        VStack(spacing: 8) {
                            HStack {
                                Button(action: {
                                    // Exit face detection mode, reset state
                                    withAnimation {
                                        isFaceDetectionActive = false
                                        detectedFaces = []
                                        modifiedImage = nil
                                    }
                                }) {
                                    Label("Cancel", systemImage: "xmark")
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Color.gray)
                                        .cornerRadius(8)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    showMaskOptions = true
                                }) {
                                    Label("Mask Faces", systemImage: "eye.slash")
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(hasFacesSelected ? Color.blue : Color.gray)
                                        .cornerRadius(8)
                                }
                                .disabled(!hasFacesSelected)
                            }
                            .padding(.horizontal)
                            
                            Text("Tap on faces to select them for masking")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if detectedFaces.isEmpty {
                                Text("No faces detected")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(detectedFaces.count) faces detected, \(detectedFaces.filter { $0.isSelected }.count) selected")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 10)
                    } else {
                        // Bottom toolbar with action buttons
                        HStack(spacing: 30) {
                            // Info button
                            Button(action: {
                                showImageInfo = true
                            }) {
                                VStack {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 24))
                                    Text("Info")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                            
                            // Obfuscate faces button
                            Button(action: detectFaces) {
                                VStack {
                                    Image(systemName: "face.dashed")
                                        .font(.system(size: 24))
                                    Text("Obfuscate")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                            
                            // Share button
                            Button(action: sharePhoto) {
                                VStack {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 24))
                                    Text("Share")
                                        .font(.caption)
                                }
                                .foregroundColor(.blue)
                            }
                            
                            // Delete button
                            Button(action: {
                                // Ensure we're setting the state variable to true
                                // which will trigger the alert presentation
                                self.showDeleteConfirmation = true
                            }) {
                                VStack {
                                    Image(systemName: "trash")
                                        .font(.system(size: 24))
                                    Text("Delete")
                                        .font(.caption)
                                }
                                .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.8))
                        .cornerRadius(12)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitle("Photo Detail", displayMode: .inline)
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Delete Photo"),
                    message: Text("Are you sure you want to delete this photo? This action cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        // Call delete function directly
                        deleteCurrentPhoto()
                    },
                    secondaryButton: .cancel()
                )
            }
            .alert(isPresented: $showBlurConfirmation) {
                Alert(
                    title: Text(maskActionTitle),
                    message: Text("Are you sure you want to \(maskActionVerb) the selected faces? This will permanently modify the photo."),
                    primaryButton: .destructive(Text(maskButtonLabel)) {
                        applyFaceMasking()
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(isPresented: $showImageInfo) {
                ImageInfoView(photo: currentPhoto)
            }
        }
    }
    
    // Face detection methods
    private func detectFaces() {
        withAnimation {
            isFaceDetectionActive = true
            processingFaces = true
        }
        
        // Clear any previous results
        detectedFaces = []
        modifiedImage = nil
        
        // Run face detection on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            faceDetector.detectFaces(in: currentPhoto.fullImage) { faces in
                // Update UI on main thread
                DispatchQueue.main.async {
                    withAnimation {
                        self.detectedFaces = faces
                        self.processingFaces = false
                    }
                }
            }
        }
    }
    
    private func toggleFaceSelection(_ face: DetectedFace) {
        // Find and toggle the selected face
        if let index = detectedFaces.firstIndex(where: { $0.id == face.id }) {
            var updatedFaces = detectedFaces
            updatedFaces[index].isSelected.toggle()
            detectedFaces = updatedFaces
        }
    }
    
    private func applyFaceMasking() {
        // Show a loading indicator while processing
        withAnimation {
            processingFaces = true
        }
        
        // Apply masking on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Use the new maskFaces method with the selected mask mode
            if let maskedImage = faceDetector.maskFaces(in: currentPhoto.fullImage, faces: detectedFaces, modes: [selectedMaskMode]) {
                // Save the masked image to the file system
                let imageData = maskedImage.jpegData(compressionQuality: 0.9) ?? Data()
                
                do {
                    try secureFileManager.savePhoto(imageData, withMetadata: currentPhoto.metadata)
                    
                    // Update UI on main thread
                    DispatchQueue.main.async {
                        withAnimation {
                            self.modifiedImage = maskedImage
                            self.processingFaces = false
                            
                            // Exit face detection mode after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    self.isFaceDetectionActive = false
                                    self.detectedFaces = []
                                }
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.processingFaces = false
                    }
                    print("Error saving masked photo: \(error.localizedDescription)")
                }
            } else {
                DispatchQueue.main.async {
                    self.processingFaces = false
                }
                print("Error creating masked image")
            }
        }
    }
    
    // Navigation functions
    private func navigateToPrevious() {
        if canGoToPrevious {
            withAnimation {
                currentIndex -= 1
                // Reset rotation when changing photos
                imageRotation = 0
                // Clear face detection state
                isFaceDetectionActive = false
                detectedFaces = []
                modifiedImage = nil
            }
        }
    }
    
    private func navigateToNext() {
        if canGoToNext {
            withAnimation {
                currentIndex += 1
                // Reset rotation when changing photos
                imageRotation = 0
                // Clear face detection state
                isFaceDetectionActive = false
                detectedFaces = []
                modifiedImage = nil
            }
        }
    }
    
    // Manually rotate image if needed
    private func rotateImage(direction: Double) {
        imageRotation += direction
        
        // Normalize to 0-360 range
        if imageRotation >= 360 {
            imageRotation -= 360
        } else if imageRotation < 0 {
            imageRotation += 360
        }
    }
    
    private func deletePhoto() {
        // This function is kept for compatibility but just calls the new implementation
        deleteCurrentPhoto()
    }
    
    private func deleteCurrentPhoto() {
        // Get the photo to delete
        let photoToDelete = currentPhoto
        
        // Set a flag to indicate we're processing (could show a spinner here)
        let isProcessing = true
        
        // Perform file deletion in a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Actually delete the file
                try self.secureFileManager.deletePhoto(filename: photoToDelete.filename)
                
                // All UI updates must happen on the main thread
                DispatchQueue.main.async {
                    // Notify the parent view about the deletion
                    if let onDelete = self.onDelete {
                        onDelete(photoToDelete)
                    }
                    
                    // If we're displaying multiple photos, we can navigate to next/previous
                    // instead of dismissing if there are still photos to display
                    if !self.allPhotos.isEmpty && self.allPhotos.count > 1 {
                        // Remove the deleted photo from our local array
                        var updatedPhotos = self.allPhotos
                        updatedPhotos.remove(at: self.currentIndex)
                        
                        if updatedPhotos.isEmpty {
                            // If no photos left, dismiss the view
                            self.dismiss()
                        } else {
                            // Adjust the current index if necessary
                            if self.currentIndex >= updatedPhotos.count {
                                self.currentIndex = updatedPhotos.count - 1
                            }
                            
                            // Update our photos array
                            self.allPhotos = updatedPhotos
                        }
                    } else {
                        // Single photo case, just dismiss the view to return to gallery
                        self.dismiss()
                    }
                }
            } catch {
                print("Error deleting photo: \(error.localizedDescription)")
                
                // Show error alert if needed
                DispatchQueue.main.async {
                    // Here you could set an error state and show an alert
                }
            }
        }
    }
    
    // Share photo method
    private func sharePhoto() {
        // Get the current photo image
        let image = displayedImage
        
        // Use UIApplication.shared.windows approach for SwiftUI integration
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            print("Could not find root view controller")
            return
        }
        
        // Create a UIActivityViewController to show the sharing options
        let activityViewController = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        // For iPad support
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Find the presented view controller to present from
        var currentController = rootViewController
        while let presented = currentController.presentedViewController {
            currentController = presented
        }
        
        // Present the share sheet from the topmost presented controller
        DispatchQueue.main.async {
            currentController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    // Preference key to get the size of the image view
    struct SizePreferenceKey: PreferenceKey {
        static var defaultValue: CGSize = .zero
        static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
            value = nextValue()
        }
    }
    
    // UIKit Image Picker wrapped for SwiftUI
    struct ImagePicker: UIViewControllerRepresentable {
        @Binding var image: UIImage?
        var onDismiss: () -> Void
        
        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.sourceType = .photoLibrary
            picker.allowsEditing = false
            return picker
        }
        
        func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let parent: ImagePicker
            
            init(_ parent: ImagePicker) {
                self.parent = parent
            }
            
            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                if let selectedImage = info[.originalImage] as? UIImage {
                    parent.image = selectedImage
                }
                
                picker.dismiss(animated: true) {
                    self.parent.onDismiss()
                }
            }
            
            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                picker.dismiss(animated: true, completion: nil)
            }
        }
    }
    //}
    
    // Extend ContentView for previews
    //struct ContentView_Previews: PreviewProvider {
    //    static var previews: some View {
    //        ContentView()
    //    }
    //}
    
    //#Preview {
    //    ContentView()
    //}
    
    // View for displaying image metadata
    struct ImageInfoView: View {
        let photo: SecurePhoto
        @Environment(\.dismiss) private var dismiss
        
        // Helper function to format bytes to readable size
        private func formatFileSize(bytes: Int) -> String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(bytes))
        }
        
        // Helper to format date
        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            return formatter.string(from: date)
        }
        
        // Helper to interpret orientation
        private func orientationString(from value: Int) -> String {
            switch value {
            case 1: return "Normal"
            case 3: return "Rotated 180°"
            case 6: return "Rotated 90° CW"
            case 8: return "Rotated 90° CCW"
            default: return "Unknown (\(value))"
            }
        }
        
        // Extract location data from EXIF
        private func locationString(from metadata: [String: Any]) -> String {
            if let gpsData = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
                var locationParts: [String] = []
                
                // Extract latitude
                if let latitudeRef = gpsData[kCGImagePropertyGPSLatitudeRef as String] as? String,
                   let latitude = gpsData[kCGImagePropertyGPSLatitude as String] as? Double {
                    let latDirection = latitudeRef == "N" ? "N" : "S"
                    locationParts.append(String(format: "%.6f°%@", latitude, latDirection))
                }
                
                // Extract longitude
                if let longitudeRef = gpsData[kCGImagePropertyGPSLongitudeRef as String] as? String,
                   let longitude = gpsData[kCGImagePropertyGPSLongitude as String] as? Double {
                    let longDirection = longitudeRef == "E" ? "E" : "W"
                    locationParts.append(String(format: "%.6f°%@", longitude, longDirection))
                }
                
                // Include altitude if available
                if let altitude = gpsData[kCGImagePropertyGPSAltitude as String] as? Double {
                    locationParts.append(String(format: "Alt: %.1fm", altitude))
                }
                
                return locationParts.isEmpty ? "Not available" : locationParts.joined(separator: ", ")
            }
            
            return "Not available"
        }
        
        var body: some View {
            NavigationView {
                Form {
                    Section(header: Text("Basic Information")) {
                        HStack {
                            Text("Filename")
                            Spacer()
                            Text(photo.filename)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Resolution")
                            Spacer()
                            Text("\(Int(photo.fullImage.size.width)) × \(Int(photo.fullImage.size.height))")
                                .foregroundColor(.secondary)
                        }
                        
                        if let imageData = photo.fullImage.jpegData(compressionQuality: 1.0) {
                            HStack {
                                Text("File Size")
                                Spacer()
                                Text(formatFileSize(bytes: imageData.count))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section(header: Text("Date Information")) {
                        if let creationDate = photo.metadata["creationDate"] as? Double {
                            HStack {
                                Text("Date Taken")
                                Spacer()
                                Text(formatDate(Date(timeIntervalSince1970: creationDate)))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No date information available")
                                .foregroundColor(.secondary)
                        }
                        
                        if let exifDict = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any],
                           let dateTimeOriginal = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                            HStack {
                                Text("Original Date")
                                Spacer()
                                Text(dateTimeOriginal)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section(header: Text("Orientation")) {
                        if let tiffDict = photo.metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
                           let orientation = tiffDict[kCGImagePropertyTIFFOrientation as String] as? Int {
                            HStack {
                                Text("Orientation")
                                Spacer()
                                Text(orientationString(from: orientation))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Normal")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section(header: Text("Location")) {
                        Text(locationString(from: photo.metadata))
                            .foregroundColor(.secondary)
                    }
                    
                    Section(header: Text("Camera Information")) {
                        if let exifDict = photo.metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
                            if let make = (photo.metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFMake as String] as? String,
                               let model = (photo.metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any])?[kCGImagePropertyTIFFModel as String] as? String {
                                HStack {
                                    Text("Camera")
                                    Spacer()
                                    Text("\(make) \(model)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let fNumber = exifDict[kCGImagePropertyExifFNumber as String] as? Double {
                                HStack {
                                    Text("Aperture")
                                    Spacer()
                                    Text(String(format: "f/%.1f", fNumber))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let exposureTime = exifDict[kCGImagePropertyExifExposureTime as String] as? Double {
                                HStack {
                                    Text("Shutter Speed")
                                    Spacer()
                                    Text("\(exposureTime < 1 ? "1/\(Int(1/exposureTime))" : String(format: "%.1f", exposureTime))s")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let isoValue = exifDict[kCGImagePropertyExifISOSpeedRatings as String] as? [Int],
                               let iso = isoValue.first {
                                HStack {
                                    Text("ISO")
                                    Spacer()
                                    Text("\(iso)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let focalLength = exifDict[kCGImagePropertyExifFocalLength as String] as? Double {
                                HStack {
                                    Text("Focal Length")
                                    Spacer()
                                    Text("\(Int(focalLength))mm")
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("No camera information available")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Display all raw metadata for debugging
                    if photo.metadata.count > 0 {
                        Section(header: Text("All Metadata")) {
                            DisclosureGroup("Raw Metadata") {
                                ForEach(photo.metadata.keys.sorted(), id: \.self) { key in
                                    VStack(alignment: .leading) {
                                        Text(key)
                                            .font(.headline)
                                            .foregroundColor(.blue)
                                        Text("\(String(describing: photo.metadata[key]!))")
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Image Information")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

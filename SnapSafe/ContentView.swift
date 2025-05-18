//
//  ContentView.swift
//  Snap Safe
//
//  Created by Bill Booth on 5/2/25.
//

import SwiftUI

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
        // Configure photo settings
        let photoSettings = AVCapturePhotoSettings()

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
    let isEditing: Bool
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

            // Delete button in edit mode
            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                }
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
    @Binding var editMode: EditMode
    @Binding var showDeleteConfirmation: Bool
    let hasSelection: Bool
    let onRefresh: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            EditButton()
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if editMode.isEditing && hasSelection {
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            } else {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }
}

// Gallery view to display the stored photos
struct SecureGalleryView: View {
    @State private var photos: [SecurePhoto] = []
    @State private var selectedPhoto: SecurePhoto?
    @State private var showFaceDetection = true  // Enable face detection by default
    @State private var editMode: EditMode = .inactive
    @State private var selectedPhotoIds = Set<UUID>()
    @State private var showDeleteConfirmation = false
    private let secureFileManager = SecureFileManager()
    @Environment(\.dismiss) private var dismiss

    // Computed properties to simplify the view
    private var isEditing: Bool {
        editMode.isEditing
    }

    private var hasSelection: Bool {
        !selectedPhotoIds.isEmpty
    }

    var body: some View {
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
                // Face detection toggle button
                ToolbarItem(placement: .navigationBarTrailing) {
                    Toggle(isOn: $showFaceDetection) {
                        Image(systemName: "face.dashed")
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .padding(.trailing, 8)
                    .labelsHidden()
                }

                // Standard gallery toolbar
                GalleryToolbar(
                    editMode: $editMode,
                    showDeleteConfirmation: $showDeleteConfirmation,
                    hasSelection: hasSelection,
                    onRefresh: loadPhotos
                )
            }
            .environment(\.editMode, $editMode)
            .onAppear(perform: loadPhotos)
            .onChange(of: selectedPhoto) { _, newValue in
                if newValue == nil {
                    loadPhotos()
                }
            }
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
                        isEditing: isEditing,
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

    // MARK: - Action methods

    private func handlePhotoTap(_ photo: SecurePhoto) {
        if isEditing {
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

        // Clear selection and exit edit mode immediately
        // for better UI responsiveness
        DispatchQueue.main.async {
            self.selectedPhotoIds.removeAll()
            self.editMode = .inactive
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

    // Used to measure the displayed image size
    @State private var imageFrameSize: CGSize = .zero

    private let faceDetector = FaceDetector()
    @Environment(\.dismiss) private var dismiss
    private let secureFileManager = SecureFileManager()

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
            VStack {
                // Navigation and photo counter
                if !allPhotos.isEmpty {
                    HStack {
                        Button(action: { navigateToPrevious() }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(canGoToPrevious ? .blue : .gray)
                        }
                        .disabled(!canGoToPrevious || isFaceDetectionActive)

                        Spacer()

                        Text("\(currentIndex + 1) of \(allPhotos.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { navigateToNext() }) {
                            Image(systemName: "chevron.right")
                                .font(.title2)
                                .foregroundColor(canGoToNext ? .blue : .gray)
                        }
                        .disabled(!canGoToNext || isFaceDetectionActive)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }

                // Photo display with proper orientation handling
                ZStack {
                    // Background color
                    Color.black.opacity(0.2)

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
                .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()

                // Action buttons and status
                VStack {
                    // Processing indicator
                    if processingFaces {
                        ProgressView("Detecting faces...")
                            .padding()
                    }

                    // Action buttons for face detection
                    if isFaceDetectionActive {
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
                                    .padding()
                                    .background(Color.gray)
                                    .cornerRadius(10)
                            }

                            Spacer()

                            Button(action: {
                                showBlurConfirmation = true
                            }) {
                                Label("Blur Faces", systemImage: "eye.slash")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(hasFacesSelected ? Color.blue : Color.gray)
                                    .cornerRadius(10)
                            }
                            .disabled(!hasFacesSelected)
                        }
                        .padding(.horizontal)

                        Text("Tap on faces to select them for blurring")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)

                        if detectedFaces.isEmpty {
                            Text("No faces detected")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 5)
                        } else {
                            Text("\(detectedFaces.count) faces detected, \(detectedFaces.filter { $0.isSelected }.count) selected")
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 5)
                        }
                    } else {
                        // Regular action buttons
                        HStack {
                            if showFaceDetection {
                                Button(action: detectFaces) {
                                    Label("Detect Faces", systemImage: "face.dashed")
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                }
                            }

                            Spacer()

                            Button(action: {
                                showDeleteConfirmation = true
                            }) {
                                Label("Delete", systemImage: "trash")
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.red)
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)

                        // Rotation controls
                        HStack(spacing: 20) {
                            Button(action: { rotateImage(direction: -90) }) {
                                Image(systemName: "rotate.left")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }

                            Button(action: { rotateImage(direction: 90) }) {
                                Image(systemName: "rotate.right")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .navigationBarTitle("Photo Detail", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !isFaceDetectionActive {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("Delete Photo"),
                message: Text("Are you sure you want to delete this photo? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    deletePhoto()
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showBlurConfirmation) {
            Alert(
                title: Text("Blur Selected Faces"),
                message: Text("Are you sure you want to blur the selected faces? This will permanently modify the photo."),
                primaryButton: .destructive(Text("Blur Faces")) {
                    applyFaceBlurring()
                },
                secondaryButton: .cancel()
            )
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

    private func applyFaceBlurring() {
        // Apply blurring on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            if let blurredImage = faceDetector.blurFaces(in: currentPhoto.fullImage, faces: detectedFaces) {
                // Save the blurred image to the file system
                let imageData = blurredImage.jpegData(compressionQuality: 0.9) ?? Data()

                do {
                    try secureFileManager.savePhoto(imageData, withMetadata: currentPhoto.metadata)

                    // Update UI on main thread
                    DispatchQueue.main.async {
                        withAnimation {
                            self.modifiedImage = blurredImage

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
                    print("Error saving blurred photo: \(error.localizedDescription)")
                }
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
        // Get the photo to delete
        let photoToDelete = currentPhoto

        // Perform file deletion in a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
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
                        // Single photo case, just dismiss
                        self.dismiss()
                    }
                }
            } catch {
                print("Error deleting photo: \(error.localizedDescription)")
            }
        }
    }
}

// Preference key to get the size of the image view
struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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

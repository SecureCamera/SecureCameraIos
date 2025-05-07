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
                // Camera view
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
            
            // Configure device for video zoom with optimal settings
            try device.lockForConfiguration()
            
            // Get zoom values from the device
            let minZoomValue: CGFloat = 1.0
            let maxZoomValue = min(device.activeFormat.videoMaxZoomFactor, 10.0) // Limit to 10x
            let defaultZoomValue: CGFloat = 1.0
            
            // Set zoom factor on the device
            device.videoZoomFactor = defaultZoomValue
            
            // Configure for optimal performance
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            device.unlockForConfiguration()

            // Create and add input
            let input = try AVCaptureDeviceInput(device: device)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            // Add photo output with high-quality settings
            if self.session.canAddOutput(self.output) {
                self.output.isHighResolutionCaptureEnabled = true
                self.session.addOutput(self.output)
            }

            // Apply all configuration changes at once
            self.session.commitConfiguration()
            
            // Update all @Published properties on the main thread
            DispatchQueue.main.async {
                self.minZoom = minZoomValue
                self.maxZoom = maxZoomValue
                self.zoomFactor = defaultZoomValue
            }
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
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
        if let initialScale = initialScale {
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
    
    // Method to handle white balance adjustment at a specific point
    func adjustWhiteBalance(at point: CGPoint) {
        guard let device = self.currentDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                // First set to auto white balance
                device.whiteBalanceMode = .continuousAutoWhiteBalance
                
                // Then lock the white balance at the current values
                // This will use the auto white balance values based on the tapped area
                let currentWhiteBalanceGains = device.deviceWhiteBalanceGains
                device.setWhiteBalanceModeLocked(with: currentWhiteBalanceGains, completionHandler: nil)
            }
            
            device.unlockForConfiguration()
        } catch {
            print("Error adjusting white balance: \(error.localizedDescription)")
        }
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
struct CameraView: UIViewRepresentable {
    @ObservedObject var cameraModel: CameraModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        // Create and configure the preview layer
        cameraModel.preview = AVCaptureVideoPreviewLayer(session: cameraModel.session)
        cameraModel.preview.frame = view.frame
        cameraModel.preview.videoGravity = .resizeAspectFill
        cameraModel.preview.connection?.videoOrientation = .portrait // Force portrait orientation
        
        // Ensure the layer is added to the view
        view.layer.addSublayer(cameraModel.preview)
        
        // Add gesture recognizers
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handlePinchGesture(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(context.coordinator.handleDoubleTapGesture(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTapGesture)
        
        // Start the session on a background thread with higher priority
        DispatchQueue.global(qos: .userInteractive).async {
            if !cameraModel.session.isRunning {
                cameraModel.session.startRunning()
            }
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the preview layer frame when the view updates
        DispatchQueue.main.async {
            cameraModel.preview?.frame = uiView.bounds
            
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
        var parent: CameraView
        private var initialScale: CGFloat = 1.0
        
        init(_ parent: CameraView) {
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
        
        // Handle double tap gesture for white balance
        @objc func handleDoubleTapGesture(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            // Convert touch point to camera coordinate
            if let layer = parent.cameraModel.preview {
                // Convert the point from the view's coordinate space to the preview layer's coordinate space
                let pointInPreviewLayer = layer.captureDevicePointConverted(fromLayerPoint: location)
                
                // Adjust white balance at this point
                parent.cameraModel.adjustWhiteBalance(at: pointInPreviewLayer)
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

// Placeholder for settings view
struct SettingsView: View {
    @State private var biometricEnabled = false
    @State private var appPIN = ""
    @State private var poisonPIN = ""
//    private let authManager = AuthenticationManager()

    var body: some View {
        EmptyView()
//        NavigationView {
//            List {
//                Section(header: Text("Authentication")) {
//                    Toggle("Enable Biometric Authentication", isOn: $biometricEnabled)
//                        .onChange(of: biometricEnabled) { newValue in
//                            authManager.isBiometricEnabled = newValue
//                        }
//                }
//
//                Section(header: Text("App PIN"), footer: Text("Set an app-specific PIN for additional security")) {
//                    SecureField("Set App PIN", text: $appPIN)
//                        .keyboardType(.numberPad)
//
//                    Button("Save App PIN") {
//                        if !appPIN.isEmpty {
//                            authManager.setAppPIN(appPIN)
//                            appPIN = ""
//                        }
//                    }
//                }
//
//                Section(header: Text("Emergency Erasure"), footer: Text("If this PIN is entered, all photos will be immediately deleted")) {
//                    SecureField("Set Emergency PIN", text: $poisonPIN)
//                        .keyboardType(.numberPad)
//
//                    Button("Save Emergency PIN") {
//                        if !poisonPIN.isEmpty {
//                            authManager.setPoisonPIN(poisonPIN)
//                            poisonPIN = ""
//                        }
//                    }
//                    .foregroundColor(.red)
//                }
//            }
//            .navigationTitle("Settings")
//            .navigationBarTitleDisplayMode(.inline)
//        }
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
            
            Button("Go Back and Take Photos", action: onDismiss)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.top, 20)
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
    @State private var showFaceDetection = false
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
                GalleryToolbar(
                    editMode: $editMode, 
                    showDeleteConfirmation: $showDeleteConfirmation,
                    hasSelection: hasSelection,
                    onRefresh: loadPhotos
                )
            }
            .environment(\.editMode, $editMode)
            .onAppear(perform: loadPhotos)
            .onChange(of: selectedPhoto) { newValue in
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
    
    // Check if navigation is possible
    private var canGoToPrevious: Bool {
        !allPhotos.isEmpty && currentIndex > 0
    }
    
    private var canGoToNext: Bool {
        !allPhotos.isEmpty && currentIndex < allPhotos.count - 1
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
                        .disabled(!canGoToPrevious)
                        
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
                        .disabled(!canGoToNext)
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
                
                // Photo display with proper orientation handling
                ZStack {
                    // Background color
                    Color.black.opacity(0.2)
                    
                    // Image display
                    Image(uiImage: currentPhoto.fullImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .rotationEffect(.degrees(imageRotation))
                        .offset(x: offset)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    // Only enable horizontal swipes if we have multiple photos
                                    if !allPhotos.isEmpty {
                                        isSwiping = true
                                        offset = gesture.translation.width
                                    }
                                }
                                .onEnded { gesture in
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
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                
                // Action buttons
                HStack {
                    if showFaceDetection {
                        Button("Detect and Blur Faces") {
                            // Face detection logic would go here
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
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
        .navigationBarTitle("Photo Detail", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
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
    }
    
    // Navigation functions
    private func navigateToPrevious() {
        if canGoToPrevious {
            withAnimation {
                currentIndex -= 1
                // Reset rotation when changing photos
                imageRotation = 0
            }
        }
    }
    
    private func navigateToNext() {
        if canGoToNext {
            withAnimation {
                currentIndex += 1
                // Reset rotation when changing photos
                imageRotation = 0
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

// Extend ContentView for previews
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
//}

//#Preview {
//    ContentView()
//}

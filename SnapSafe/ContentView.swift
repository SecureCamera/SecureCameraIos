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
        .onAppear {
            // Request camera permission when the app launches
            cameraModel.checkPermissions()
        }
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

    // Storage managers
    private let secureFileManager = SecureFileManager()

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isPermissionGranted = true
            self.setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { status in
                if status {
                    DispatchQueue.main.async {
                        self.isPermissionGranted = true
                        self.setupCamera()
                    }
                }
            }
        default:
            self.isPermissionGranted = false
            self.alert = true
        }
    }

    func setupCamera() {
        do {
            self.session.beginConfiguration()

            // Add device input
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("Failed to get camera device")
                return
            }

            let input = try AVCaptureDeviceInput(device: device)

            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }

            // Add photo output
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }

            self.session.commitConfiguration()
        } catch {
            print("Error setting up camera: \(error.localizedDescription)")
        }
    }

    func capturePhoto() {
        // Configure photo settings
        let photoSettings = AVCapturePhotoSettings()

        self.output.capturePhoto(with: photoSettings, delegate: self)
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
            DispatchQueue.main.async {
                self.recentImage = image
            }
        }
    }

    private func savePhoto(_ imageData: Data) {
        // Extract basic metadata if possible
        var metadata: [String: Any] = [:]

        if let source = CGImageSourceCreateWithData(imageData as CFData, nil) {
            if let imageMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                metadata = imageMetadata
            }
        }

        // Save the photo without encryption for now
        do {
            let _ = try secureFileManager.savePhoto(imageData, withMetadata: metadata)
            print("Photo saved successfully")
        } catch {
            print("Error saving photo: \(error.localizedDescription)")
        }
    }
}

// SwiftUI wrapper for the camera preview
struct CameraView: UIViewRepresentable {
    @ObservedObject var cameraModel: CameraModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)

        cameraModel.preview = AVCaptureVideoPreviewLayer(session: cameraModel.session)
        cameraModel.preview.frame = view.frame
        cameraModel.preview.videoGravity = .resizeAspectFill

        view.layer.addSublayer(cameraModel.preview)

        // Start the session on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            cameraModel.session.startRunning()
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
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
                PhotoDetailView(
                    photo: photo,
                    showFaceDetection: showFaceDetection,
                    onDelete: { _ in loadPhotos() }
                )
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
    
    private func loadPhotos() {
        do {
            let photoData = try secureFileManager.loadAllPhotos()
            
            // Convert loaded photos to SecurePhoto objects
            self.photos = photoData.map { (filename, data, metadata) in
                // Create a full image from the data
                let fullImage = UIImage(data: data) ?? UIImage()
                
                // Use the same image for thumbnail for simplicity
                return SecurePhoto(
                    filename: filename,
                    thumbnail: fullImage,
                    fullImage: fullImage,
                    metadata: metadata
                )
            }
        } catch {
            print("Error loading photos: \(error.localizedDescription)")
        }
    }
    
    private func deletePhoto(_ photo: SecurePhoto) {
        do {
            try secureFileManager.deletePhoto(filename: photo.filename)
            
            // Remove from the local array
            withAnimation {
                photos.removeAll { $0.id == photo.id }
                if selectedPhotoIds.contains(photo.id) {
                    selectedPhotoIds.remove(photo.id)
                }
            }
        } catch {
            print("Error deleting photo: \(error.localizedDescription)")
        }
    }
    
    private func deleteSelectedPhotos() {
        for id in selectedPhotoIds {
            if let photo = photos.first(where: { $0.id == id }) {
                deletePhoto(photo)
            }
        }
        selectedPhotoIds.removeAll()
        
        // Exit edit mode after deletion
        editMode = .inactive
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

struct PhotoDetailView: View {
    let photo: SecurePhoto
    let showFaceDetection: Bool
    var onDelete: ((SecurePhoto) -> Void)? = nil
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss
    private let secureFileManager = SecureFileManager()

    var body: some View {
        VStack {
            Image(uiImage: photo.fullImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()

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
            .padding()
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

    private func deletePhoto() {
        do {
            try secureFileManager.deletePhoto(filename: photo.filename)

            // Notify the parent view about the deletion
            if let onDelete = onDelete {
                onDelete(photo)
            }

            dismiss() // Close the detail view after deletion
        } catch {
            print("Error deleting photo: \(error.localizedDescription)")
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

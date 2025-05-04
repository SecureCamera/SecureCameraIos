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
    
    var body: some View {
        ZStack {
            if !isAuthenticated {
                // Authentication screen
                AuthenticationView(isAuthenticated: $isAuthenticated)
            } else {
                // Camera view
                CameraView(cameraModel: cameraModel)
                    .edgesIgnoringSafeArea(.all)
                
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
}

// Camera model that handles the AVFoundation functionality
class CameraModel: ObservableObject {
    @Published var isPermissionGranted = false
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    
    // Encryption and secure storage managers
//    private let encryptionManager = EncryptionManager()
//    private let secureFileManager = SecureFileManager()
    
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
        
//        self.output.capturePhoto(with: photoSettings, delegate: self)
    }
}

// Extend CameraModel to handle photo capture delegate
//extension CameraModel: AVCapturePhotoCaptureDelegate {
//    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
//        if let error = error {
//            print("Error capturing photo: \(error.localizedDescription)")
//            return
//        }
//        
//        guard let imageData = photo.fileDataRepresentation() else {
//            print("Failed to get image data")
//            return
//        }
//        
//         Extract EXIF data
//        if let source = CGImageSourceCreateWithData(imageData as CFData, nil) {
//            if let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
//                processAndSecurePhoto(imageData, metadata: metadata)
//            }
//        }
//    }
//
//    private func processAndSecurePhoto(_ imageData: Data, metadata: [String: Any]) {
//        // Process EXIF and location data
//        var processedMetadata = metadata
//        
//        // Extract GPS data if available
//        if let gpsInfo = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
//            // Process location data
//            processedMetadata["extractedLocation"] = gpsInfo
//            
//            // Remove GPS data from the original metadata for security
//            processedMetadata.removeValue(forKey: kCGImagePropertyGPSDictionary as String)
//        }
//        
//        // Encrypt and save the photo
//        do {
//            let encryptedData = try encryptionManager.encryptData(imageData)
//            try secureFileManager.saveEncryptedPhoto(encryptedData, withMetadata: processedMetadata)
//        } catch {
//            print("Error securing photo: \(error.localizedDescription)")
//        }
//    }
//}

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

// Placeholder for the secure gallery view
struct SecureGalleryView: View {
    @State private var photos: [SecurePhoto] = []
    @State private var selectedPhoto: SecurePhoto?
    @State private var showFaceDetection = false
//    private let secureFileManager = SecureFileManager()
//    private let encryptionManager = EncryptionManager()
    
    var body: some View {
        EmptyView()
//        NavigationView {
//            ScrollView {
//                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
//                    ForEach(photos) { photo in
//                        Image(uiImage: photo.thumbnail)
//                            .resizable()
//                            .aspectRatio(contentMode: .fill)
//                            .frame(width: 100, height: 100)
//                            .clipShape(RoundedRectangle(cornerRadius: 10))
//                            .onTapGesture {
//                                selectedPhoto = photo
//                            }
//                    }
//                }
//                .padding()
//            }
//            .navigationTitle("Secure Gallery")
//            .navigationBarTitleDisplayMode(.inline)
//            .navigationBarItems(trailing: Button(action: {
//                showFaceDetection.toggle()
//            }) {
//                Image(systemName: "face.dashed")
//            })
//            .onAppear {
//                loadPhotos()
//            }
//            .sheet(item: $selectedPhoto) { photo in
//                PhotoDetailView(photo: photo, showFaceDetection: showFaceDetection)
//            }
//        }
    }
    
    private func loadPhotos() {
        // In a real implementation, this would load the encrypted photos
        // decrypt them, and create thumbnails
    }
}

// Placeholder structs to make the code compile
struct SecurePhoto: Identifiable {
    let id = UUID()
    let thumbnail: UIImage
    let fullImage: UIImage
    let metadata: [String: Any]
}

struct PhotoDetailView: View {
    let photo: SecurePhoto
    let showFaceDetection: Bool
    
    var body: some View {
        VStack {
            Image(uiImage: photo.fullImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
            
            if showFaceDetection {
                Button("Detect and Blur Faces") {
                    // Face detection logic would go here
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding()
            }
        }
    }
}

// Extend ContentView for previews
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

//#Preview {
//    ContentView()
//}

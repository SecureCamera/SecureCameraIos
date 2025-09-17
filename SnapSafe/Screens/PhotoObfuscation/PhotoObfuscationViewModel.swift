//
//  PhotoObfuscationViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/11/25.
//

import UIKit
import SwiftUI
import FactoryKit
import Combine
import Logging

@MainActor
final class PhotoObfuscationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentImage: UIImage?
    @Published var isImageLoading: Bool = false
    
    // Face detection states
    @Published var isFaceDetectionActive = false
    @Published var detectedFaces: [DetectedFace] = []
    @Published var processingFaces = false
    @Published var modifiedImage: UIImage?
    @Published var showBlurConfirmation = false
    @Published var selectedMaskMode: MaskMode = .blur
    @Published var showMaskOptions = false
    
    @Published var imageFrameSize: CGSize = .zero
    
    // MARK: - Private Properties
    
    private let photoDef: PhotoDef
    private let faceDetector = FaceDetector()
    private weak var currentActivityController: UIActivityViewController?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Callbacks
    
    var onSave: ((UIImage) -> Void)?
    var onDismiss: (() -> Void)?
    
    // MARK: - Dependencies
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.prepareForSharingUseCase)
    private var prepareForSharingUseCase: PrepareForSharingUseCase
    
    // MARK: - Initialization
    
    init(photoDef: PhotoDef, onSave: ((UIImage) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.photoDef = photoDef
        self.onSave = onSave
        self.onDismiss = onDismiss
        setupSecurityObservers()
        
        // Load the image immediately
        Task {
            await loadImage()
        }
    }
    
    // MARK: - Computed Properties
    
    var displayedImage: UIImage {
        if isFaceDetectionActive, let modified = modifiedImage {
            return modified
        } else {
            return currentImage ?? UIImage(systemName: "photo")!
        }
    }
    
    var hasFacesSelected: Bool {
        detectedFaces.contains { $0.isSelected }
    }
    
    var maskActionTitle: String {
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
    
    var maskActionVerb: String {
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
    
    var maskButtonLabel: String {
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
    
    // MARK: - Image Loading
    
    private func loadImage() async {
        isImageLoading = true
        
        do {
            let image = try await secureImageRepository.readImage(photoDef)
            await MainActor.run {
                self.currentImage = image
                self.isImageLoading = false
            }
        } catch {
            Logger.storage.error("Error loading image for obfuscation", metadata: [
                "photoName": .string(photoDef.photoName),
                "error": .string(String(describing: error))
            ])
            await MainActor.run {
                self.currentImage = UIImage(systemName: "photo")
                self.isImageLoading = false
            }
        }
    }
    
    // MARK: - Face Detection Methods
    
    func detectFaces() {
        guard let imageToProcess = currentImage else { return }

        // Maintain current image frame size to prevent shifting
        let currentFrameSize = imageFrameSize

        withAnimation {
            isFaceDetectionActive = true
            processingFaces = true
        }

        detectedFaces = []
        modifiedImage = nil

        Task(priority: .userInitiated) {
            self.faceDetector.detectFaces(in: imageToProcess) { faces in
                Task { @MainActor in
                    withAnimation {
                        self.detectedFaces = faces
                        self.processingFaces = false
                        // Ensure frame size remains consistent
                        if self.imageFrameSize != currentFrameSize {
                            self.imageFrameSize = currentFrameSize
                        }
                    }
                }
            }
        }
    }
    
    func toggleFaceSelection(_ face: DetectedFace) {
        if let index = detectedFaces.firstIndex(where: { $0.id == face.id }) {
            let updatedFaces = detectedFaces
            updatedFaces[index].isSelected.toggle()
            detectedFaces = updatedFaces
        }
    }
    
    func applyFaceMasking() {
        guard let imageToProcess = currentImage else { return }
        
        withAnimation {
            processingFaces = true
        }
        
        Task(priority: .userInitiated) {
            let facesToMask = self.detectedFaces
            let maskMode = self.selectedMaskMode
            
            // Process the image
            if let maskedImage = self.faceDetector.maskFaces(in: imageToProcess, faces: facesToMask, modes: [maskMode]) {
                await MainActor.run {
                    withAnimation {
                        self.currentImage = maskedImage
                        self.modifiedImage = maskedImage
                        self.processingFaces = false
                    }
                }
                
                // Wait 2 seconds then reset face detection state
                try await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation {
                        self.isFaceDetectionActive = false
                        self.detectedFaces = []
                        self.modifiedImage = nil
                    }
                }
            } else {
                await MainActor.run {
                    self.processingFaces = false
                }
                Logger.storage.error("Error creating masked image")
            }
        }
    }
    
    // MARK: - Save and Share Methods
    
    func saveChanges() {
        let imageToSave = displayedImage
        
        Task(priority: .userInitiated) {
            // Save the modified image to the file system
            guard let imageData = imageToSave.jpegData(compressionQuality: 0.9) else {
                Logger.storage.error("Error creating JPEG data for obfuscated image")
                return
            }
            
            do {
                try await secureImageRepository.updateImage(photoDef, newImageData: imageData)
                Logger.storage.info("Successfully saved obfuscated image", metadata: [
                    "photoName": .string(photoDef.photoName)
                ])
                
                await MainActor.run {
                    // Call the save callback with the modified image
                    self.onSave?(imageToSave)
                }
            } catch {
                Logger.storage.error("Error saving obfuscated image", metadata: [
                    "photoName": .string(photoDef.photoName),
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }
    
    func sharePhoto() {
        let image = displayedImage
        
        // Find the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController
        else {
            Logger.ui.error("Could not find root view controller for sharing")
            return
        }
        
        // Find the presented view controller to present from
        var currentController = rootViewController
        while let presented = currentController.presentedViewController {
            currentController = presented
        }
        
        // Convert image to data for sharing with UUID filename
        if let imageData = image.jpegData(compressionQuality: 0.9) {
            do {
                // Prepare photo for sharing with UUID filename
                let fileURL = try prepareForSharingUseCase.preparePhotoForSharing(imageData: imageData)
                
                Logger.ui.debug("Sharing obfuscated photo", metadata: [
                    "filename": .string(fileURL.lastPathComponent)
                ])
                
                // Create a UIActivityViewController to show the sharing options with the file
                let activityViewController = UIActivityViewController(
                    activityItems: [fileURL],
                    applicationActivities: nil
                )
                
                // For iPad support
                if let popover = activityViewController.popoverPresentationController {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                // Store reference and present the share sheet
                currentActivityController = activityViewController
                Task { @MainActor in
                    currentController.present(activityViewController, animated: true) {
                        Logger.ui.debug("Share sheet presented successfully for obfuscated photo")
                    }
                }
            } catch {
                Logger.ui.error("Error preparing obfuscated photo for sharing", metadata: [
                    "error": .string(error.localizedDescription)
                ])
                
                // Fallback to sharing just the image if file preparation fails
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
                
                // Store reference and present the share sheet
                currentActivityController = activityViewController
                Task { @MainActor in
                    currentController.present(activityViewController, animated: true) {
                        Logger.ui.debug("Share sheet presented successfully for obfuscated photo (image fallback)")
                    }
                }
            }
        }
    }
    
    func cancel() {
        onDismiss?()
    }
    
    // MARK: - Private Methods
    
    private func setupSecurityObservers() {
        // Monitor authorization state changes to dismiss alerts when unauthorized
        authorizationRepository.isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthorized in
                if !isAuthorized {
                    self?.dismissAllAlerts()
                }
            }
            .store(in: &cancellables)
    }
    
    private func dismissAllAlerts() {
        // Dismiss all active alert states
        showBlurConfirmation = false
        showMaskOptions = false
        
        // Dismiss any currently presented activity controller (iOS export dialog)
        currentActivityController?.dismiss(animated: false, completion: nil)
        currentActivityController = nil
    }
}

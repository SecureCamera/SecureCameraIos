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
    @Published var showObscureConfirmation = false
    @Published var showManualBoxObscureConfirmation = false

    // Manual box addition state
    @Published var isAddingBox = false
    
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

    var hasManualBoxesSelected: Bool {
        detectedFaces.contains { $0.isSelected && $0.isUserCreated }
    }
    
    var maskActionTitle: String {
        return "Obscure Selected Faces"
    }

    var maskActionVerb: String {
        return "obscure"
    }

    var maskButtonLabel: String {
        return "Obscure Faces"
    }

    var manualBoxActionTitle: String {
        return "Obscure Selected Areas"
    }

    var manualBoxButtonLabel: String {
        return "Obscure Areas"
    }
    
    // MARK: - Image Loading
    
    private func loadImage() async {
        isImageLoading = true
        
        do {
            let data = try await secureImageRepository.readImage(photoDef)
            guard let image = UIImage(data: data) else { throw ImageRepositoryError.invalidImageData }
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
    
    func applyFaceObscuring() {
        guard let imageToProcess = currentImage else { return }

        withAnimation {
            processingFaces = true
        }

        Task(priority: .userInitiated) {
            let facesToMask = self.detectedFaces

            // Process the image using pixelate mode only
            if let maskedImage = self.faceDetector.maskFaces(in: imageToProcess, faces: facesToMask, modes: [.pixelate]) {
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
                Logger.storage.error("Error creating obscured image")
            }
        }
    }

    func applyManualBoxObscuring() {
        guard let imageToProcess = currentImage else { return }

        withAnimation {
            processingFaces = true
        }

        Task(priority: .userInitiated) {
            // Only process user-created faces
            let boxesToMask = self.detectedFaces.filter { $0.isUserCreated }

            // Process the image using pixelate mode only
            if let maskedImage = self.faceDetector.maskFaces(in: imageToProcess, faces: boxesToMask, modes: [.pixelate]) {
                await MainActor.run {
                    withAnimation {
                        self.currentImage = maskedImage
                        self.modifiedImage = maskedImage
                        self.processingFaces = false
                    }
                }

                // Wait 2 seconds then reset manual box state
                try await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation {
                        // Remove processed manual boxes from the list
                        self.detectedFaces.removeAll { $0.isUserCreated }
                        self.modifiedImage = nil
                    }
                }
            } else {
                await MainActor.run {
                    self.processingFaces = false
                }
                Logger.storage.error("Error creating obscured image for manual boxes")
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

    // MARK: - Manual Box Methods

    func startAddingBoxes() {
        isAddingBox = true
        createBoxAtCenter()
    }

    func stopAddingBoxes() {
        isAddingBox = false
    }

    func clearManualBoxes() {
        detectedFaces.removeAll { $0.isUserCreated }
    }

    func createBoxAtCenter() {
        guard let img = currentImage else { return }
        let centerPoint = CGPoint(x: img.size.width / 2, y: img.size.height / 2)
        let size: CGFloat = 900
        let rect = CGRect(x: centerPoint.x - size/2, y: centerPoint.y - size/2, width: size, height: size)
        let clamped = clamp(rect, in: img.size)
        detectedFaces.append(DetectedFace(bounds: clamped, isSelected: true, isUserCreated: true))
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
        showObscureConfirmation = false
        showManualBoxObscureConfirmation = false

        // Dismiss any currently presented activity controller (iOS export dialog)
        currentActivityController?.dismiss(animated: false, completion: nil)
        currentActivityController = nil
    }
}


extension PhotoObfuscationViewModel {
    // Toggle using the face's UUID instead of array index (stable on reordering)
    func toggleFaceSelection(id: UUID) {
        guard let idx = detectedFaces.firstIndex(where: { $0.id == id }) else { return }
        detectedFaces[idx].isSelected.toggle()
    }

    // Set absolute position for smooth dragging
    func setFacePosition(id: UUID, to newBounds: CGRect) {
        guard let img = currentImage, let idx = detectedFaces.firstIndex(where: { $0.id == id }) else { return }
        detectedFaces[idx].bounds = clamp(newBounds, in: img.size)
    }

    // Set absolute size for smooth resizing
    func setFaceSize(id: UUID, to newBounds: CGRect) {
        guard let img = currentImage, let idx = detectedFaces.firstIndex(where: { $0.id == id }) else { return }
        detectedFaces[idx].bounds = clamp(newBounds, in: img.size)
    }

    // MARK: - Helpers

    private func clamp(_ rect: CGRect, in imageSize: CGSize) -> CGRect {
        var x = max(0, rect.origin.x)
        var y = max(0, rect.origin.y)
        var w = rect.width
        var h = rect.height

        if x + w > imageSize.width { x = min(x, imageSize.width - 1); w = imageSize.width - x }
        if y + h > imageSize.height { y = min(y, imageSize.height - 1); h = imageSize.height - y }
        return CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
    }
}

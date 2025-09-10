//
//  PhotoDetailViewModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import UIKit
import SwiftUI
import FactoryKit
import Combine

@MainActor
class PhotoDetailViewModel: ObservableObject {
    @Published var photoFiles: [PhotoDef] = []
    private var singlePhotoFile: PhotoDef?
    
    @Published var currentIndex: Int = 0
    @Published var currentImage: UIImage?
    @Published var isImageLoading: Bool = false
    
    // Callback handlers
    var onDelete: ((PhotoDef) -> Void)?
    var onDismiss: (() -> Void)?
    
    // UI state variables
    @Published var showDeleteConfirmation = false
    @Published var imageRotation: Double = 0
    @Published var offset: CGFloat = 0
    @Published var isSwiping: Bool = false
    
    // Zoom and pan states
    @Published var currentScale: CGFloat = 1.0
    @Published var dragOffset: CGSize = .zero
    @Published var lastScale: CGFloat = 1.0
    @Published var isZoomed: Bool = false
    @Published var lastDragPosition: CGSize = .zero
    
    // Face detection states
    @Published var isFaceDetectionActive = false
    @Published var detectedFaces: [DetectedFace] = []
    @Published var processingFaces = false
    @Published var modifiedImage: UIImage?
    @Published var showBlurConfirmation = false
    @Published var selectedMaskMode: MaskMode = .blur
    @Published var showMaskOptions = false
    
    @Published var showImageInfo = false
    
    @Published var imageFrameSize: CGSize = .zero
    
    private let faceDetector = FaceDetector()
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.clock)
    private var clock: Clock
    
    // MARK: - Dependencies
    
    @InjectedObject(\.securityOverlayViewModel) 
    private var securityViewModel: SecurityOverlayViewModel
    private var cancellables = Set<AnyCancellable>()
    
    // Track currently presented activity controller for dismissal
    private weak var currentActivityController: UIActivityViewController?
    
    let showFaceDetection: Bool
    
    // MARK: - Initialization
    
    init(photo: SecurePhoto, showFaceDetection: Bool, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.singlePhotoFile = mapToPhotoDef(photo)
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        setupSecurityObservers()
        
        // Load the image immediately
        Task {
            await loadCurrentImage()
        }
    }
    
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.photoFiles = mapToPhotoDefs(allPhotos)
        self.currentIndex = initialIndex
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        setupSecurityObservers()
        
        // Load the current image immediately
        Task {
            await loadCurrentImage()
        }
    }
    
    // MARK: - Computed Properties
    var currentPhotoDef: PhotoDef? {
        if !photoFiles.isEmpty {
            return photoFiles[currentIndex]
        } else {
            return singlePhotoFile
        }
    }
    
    var displayedImage: UIImage {
        if isFaceDetectionActive, let modified = modifiedImage {
            return modified
        } else {
            return currentImage ?? UIImage(systemName: "photo")!
        }
    }
    
    // MARK: - Image Loading
    
    private func loadCurrentImage() async {
        guard let photoDef = currentPhotoDef else { return }
        
        isImageLoading = true
        
        do {
            let image = try await secureImageRepository.readImage(photoDef)
            await MainActor.run {
                self.currentImage = image
                self.isImageLoading = false
                MemoryManager.shared.checkMemoryUsage()
            }
        } catch {
            print("Error loading image: \(error)")
            await MainActor.run {
                self.currentImage = UIImage(systemName: "photo")
                self.isImageLoading = false
            }
        }
    }
    
    var canGoToPrevious: Bool {
        !photoFiles.isEmpty && currentIndex > 0
    }
    
    var canGoToNext: Bool {
        !photoFiles.isEmpty && currentIndex < photoFiles.count - 1
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
    
    // MARK: - Face Detection Methods
    
    func detectFaces() {
        guard let imageToProcess = currentImage else { return }
        
        withAnimation {
            isFaceDetectionActive = true
            processingFaces = true
        }
        
        detectedFaces = []
        modifiedImage = nil
        
        Task(priority: .userInitiated) {
            self.faceDetector.detectFaces(in: imageToProcess) { faces in
                DispatchQueue.main.async {
                    withAnimation {
                        self.detectedFaces = faces
                        self.processingFaces = false
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
        guard let imageToProcess = currentImage,
              let currentPhotoDef = currentPhotoDef else { return }
        
        withAnimation {
            processingFaces = true
        }
        
        Task(priority: .userInitiated) {
            let facesToMask = self.detectedFaces
            let maskMode = self.selectedMaskMode
            
            // Process the image
            if let maskedImage = self.faceDetector.maskFaces(in: imageToProcess, faces: facesToMask, modes: [maskMode]) {
                // Save the masked image to the file system
                guard let imageData = maskedImage.jpegData(compressionQuality: 0.9) else {
                    DispatchQueue.main.async {
                        self.processingFaces = false
                    }
                    print("Error creating JPEG data")
                    return
                }
                
                do {
                    try await self.secureImageRepository.updateImage(currentPhotoDef, newImageData: imageData)
                    
                    DispatchQueue.main.async {
                        withAnimation {
                            self.currentImage = maskedImage
                            self.modifiedImage = maskedImage
                            self.processingFaces = false
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    self.isFaceDetectionActive = false
                                    self.detectedFaces = []
                                    self.modifiedImage = nil
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
    
    // MARK: - Navigation Methods
    
    func preloadAdjacentPhotos() {
        guard !photoFiles.isEmpty else { return }
        
        // Preload previous photo if available
        if currentIndex > 0 {
            let prevIndex = currentIndex - 1
            let prevPhotoDef = photoFiles[prevIndex]
            
            // Preload thumbnail in background
            Task(priority: .userInitiated) {
                _ = try? await secureImageRepository.readThumbnail(prevPhotoDef)
            }
        }
        
        // Preload next photo if available
        if currentIndex < photoFiles.count - 1 {
            let nextIndex = currentIndex + 1
            let nextPhotoDef = photoFiles[nextIndex]
            
            // Preload thumbnail in background
            Task(priority: .userInitiated) {
                _ = try? await secureImageRepository.readThumbnail(nextPhotoDef)
            }
        }
    }
    
    func navigateToPrevious() {
        print("🟢 PhotoDetailViewModel: navigateToPrevious called")
        if canGoToPrevious {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentIndex -= 1
                // Reset rotation when changing photos
                imageRotation = 0
                // Reset zoom and pan
                resetZoomAndPan()
                // Clear face detection state
                isFaceDetectionActive = false
                detectedFaces = []
                modifiedImage = nil
                // Reset any navigation offsets
                offset = 0
                isSwiping = false
            }
            
            // Load the new current image
            Task {
                await loadCurrentImage()
            }
            
            // Preload adjacent photos for smoother navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.preloadAdjacentPhotos()
            }
        }
    }
    
    func navigateToNext() {
        print("🟢 PhotoDetailViewModel: navigateToNext called")
        if canGoToNext {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentIndex += 1
                // Reset rotation when changing photos
                imageRotation = 0
                // Reset zoom and pan
                resetZoomAndPan()
                // Clear face detection state
                isFaceDetectionActive = false
                detectedFaces = []
                modifiedImage = nil
                // Reset any navigation offsets
                offset = 0
                isSwiping = false
            }
            
            // Load the new current image
            Task {
                await loadCurrentImage()
            }
            
            // Preload adjacent photos for smoother navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.preloadAdjacentPhotos()
            }
        }
    }
    
    // MARK: - Image Manipulation
    
    func resetZoomAndPan() {
        withAnimation(.spring()) {
            currentScale = 1.0
            dragOffset = .zero
            lastScale = 1.0
            isZoomed = false
        }
        // Reset the last drag position outside of animation to avoid jumps
        lastDragPosition = .zero
    }
    
    func rotateImage(direction: Double) {
        // Reset any zoom or panning when rotating
        resetZoomAndPan()
        
        // Apply rotation
        imageRotation += direction
        
        // Normalize to 0-360 range
        if imageRotation >= 360 {
            imageRotation -= 360
        } else if imageRotation < 0 {
            imageRotation += 360
        }
    }
    
    // MARK: - Photo Management
    
    func deletePhoto() {
        deleteCurrentPhoto()
    }
    
    func deleteCurrentPhoto() {
        print("deleteCurrentPhoto called - starting deletion process")
        
        guard let photoDefToDelete = currentPhotoDef else { return }
        
        // Perform file deletion in a background thread
        Task(priority: .userInitiated) {
            // Actually delete the file
            print("Attempting to delete file: \(photoDefToDelete.photoName)")
            self.secureImageRepository.deleteImage(photoDefToDelete)
            print("File deletion successful")
            
            // All UI updates must happen on the main thread
            await MainActor.run {
                print("Calling onDelete callback")
                // Notify the parent view about the deletion
                if let onDelete = self.onDelete {
                    onDelete(photoDefToDelete)
                }
                
                // If we're displaying multiple photos, we can navigate to next/previous
                // instead of dismissing if there are still photos to display
                if !self.photoFiles.isEmpty && self.photoFiles.count > 1 {
                    // Remove the deleted photo from our local array
                    self.photoFiles.remove(at: self.currentIndex)
                    
                    if self.photoFiles.isEmpty {
                        // If no photos left, call dismiss handler
                        if let onDismiss = self.onDismiss {
                            onDismiss()
                        }
                    } else {
                        // Adjust the current index if necessary
                        if self.currentIndex >= self.photoFiles.count {
                            self.currentIndex = self.photoFiles.count - 1
                        }
                        
                        // Load the new current image
                        Task {
                            await self.loadCurrentImage()
                        }
                    }
                } else {
                    // Single photo case, call dismiss handler
                    if let onDismiss = self.onDismiss {
                        onDismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Sharing
    
    func sharePhoto() {
        // Get the current photo image
        let image = displayedImage
        
        // Find the root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController
        else {
            print("Could not find root view controller")
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
                let fileURL = try secureFileManager.preparePhotoForSharing(imageData: imageData)
                
                print("Sharing photo with UUID filename: \(fileURL.lastPathComponent)")
                
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
                DispatchQueue.main.async {
                    currentController.present(activityViewController, animated: true) {
                        print("Share sheet presented successfully")
                    }
                }
            } catch {
                print("Error preparing photo for sharing: \(error.localizedDescription)")
                
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
                DispatchQueue.main.async {
                    currentController.present(activityViewController, animated: true) {
                        print("Share sheet presented successfully (image fallback)")
                    }
                }
            }
        } else {
            // Fallback to sharing just the image if data conversion fails
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
            DispatchQueue.main.async {
                currentController.present(activityViewController, animated: true) {
                    print("Share sheet presented successfully (image fallback)")
                }
            }
        }
    }
    
    // MARK: - View Lifecycle
    
    func onAppear() {
        // Preload adjacent photos for smoother navigation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.preloadAdjacentPhotos()
        }
    }
    
    func onDisappear() {
        // Clean up when view disappears
        if let onDismiss = onDismiss {
            onDismiss()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupSecurityObservers() {
        // Monitor security overlay dismissAllAlerts to dismiss any active alerts
        securityViewModel.$dismissAllAlerts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldDismiss in
                if shouldDismiss {
                    self?.dismissAllAlerts()
                }
            }
            .store(in: &cancellables)
            
        // Monitor security overlay state changes to dismiss alerts when privacy shield appears
        securityViewModel.$currentOverlayState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] overlayState in
                if overlayState == .privacyShield {
                    self?.dismissAllAlerts()
                }
            }
            .store(in: &cancellables)
    }
    
    private func dismissAllAlerts() {
        // Dismiss all active alert states
        showDeleteConfirmation = false
        showBlurConfirmation = false
        showMaskOptions = false
        showImageInfo = false
        
        // Dismiss any currently presented activity controller (iOS export dialog)
        currentActivityController?.dismiss(animated: false, completion: nil)
        currentActivityController = nil
    }
}

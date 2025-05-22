//
//  PhotoDetailViewModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import UIKit
import SwiftUI

class PhotoDetailViewModel: ObservableObject {
    // Single photo reference
    private var photo: SecurePhoto?
    
    // For multiple photos case
    @Published var allPhotos: [SecurePhoto] = []
    @Published var currentIndex: Int = 0
    
    // Callback handlers
    var onDelete: ((SecurePhoto) -> Void)?
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
    
    // Image info states
    @Published var showImageInfo = false
    
    // Used to measure the displayed image size
    @Published var imageFrameSize: CGSize = .zero
    
    // Services
    private let faceDetector = FaceDetector()
    private let secureFileManager = SecureFileManager()
    
    // Flag for feature availability
    let showFaceDetection: Bool
    
    // MARK: - Initialization
    
    init(photo: SecurePhoto, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.photo = photo
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.allPhotos = allPhotos
        self.currentIndex = initialIndex
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    // MARK: - Computed Properties
    
    // Get the current photo to display
    var currentPhoto: SecurePhoto {
        if !allPhotos.isEmpty {
            // Set visibility state of photos
            for (index, photo) in allPhotos.enumerated() {
                if index == currentIndex {
                    photo.isVisible = true
                } else {
                    // Mark photos far from current as invisible for memory management
                    let distance = abs(index - currentIndex)
                    if distance > 3 {
                        photo.markAsInvisible()
                    }
                }
            }
            return allPhotos[currentIndex]
        } else if let photo = photo {
            photo.isVisible = true
            return photo
        } else {
            // Should never happen but just in case
            return SecurePhoto(filename: "", thumbnail: UIImage(), fullImage: UIImage(), metadata: [:])
        }
    }
    
    // Get the image to display (original or modified)
    var displayedImage: UIImage {
        if isFaceDetectionActive, let modified = modifiedImage {
            return modified
        } else {
            let image = currentPhoto.fullImage
            // Trigger memory cleanup after loading the current image
            DispatchQueue.main.async {
                MemoryManager.shared.checkMemoryUsage()
            }
            return image
        }
    }
    
    // Check if navigation is possible
    var canGoToPrevious: Bool {
        !allPhotos.isEmpty && currentIndex > 0
    }
    
    var canGoToNext: Bool {
        !allPhotos.isEmpty && currentIndex < allPhotos.count - 1
    }
    
    // Check if any faces are selected for masking
    var hasFacesSelected: Bool {
        detectedFaces.contains { $0.isSelected }
    }
    
    // Computed properties for mask action text
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
        withAnimation {
            isFaceDetectionActive = true
            processingFaces = true
        }
        
        // Clear any previous results
        detectedFaces = []
        modifiedImage = nil
        
        // Run face detection on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Use autoreleasepool to ensure memory is released promptly after processing
            autoreleasepool {
                let imageToProcess = self.currentPhoto.fullImage
                
                self.faceDetector.detectFaces(in: imageToProcess) { faces in
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
    }
    
    func toggleFaceSelection(_ face: DetectedFace) {
        // Find and toggle the selected face
        if let index = detectedFaces.firstIndex(where: { $0.id == face.id }) {
            var updatedFaces = detectedFaces
            updatedFaces[index].isSelected.toggle()
            detectedFaces = updatedFaces
        }
    }
    
    func applyFaceMasking() {
        // Show a loading indicator while processing
        withAnimation {
            processingFaces = true
        }
        
        // Apply masking on a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            // Use autoreleasepool to ensure memory is released promptly
            autoreleasepool {
                // Get the image to process, copy of metadata and selected mode
                let imageToProcess = self.currentPhoto.fullImage
                let facesToMask = self.detectedFaces
                let metadataCopy = self.currentPhoto.metadata
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
                        try self.secureFileManager.savePhoto(imageData, withMetadata: metadataCopy)
                        
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
                                        
                                        // Force memory cleanup
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
    }
    
    // MARK: - Navigation Methods
    
    func preloadAdjacentPhotos() {
        guard !allPhotos.isEmpty else { return }
        
        // Preload previous photo if available
        if currentIndex > 0 {
            let prevIndex = currentIndex - 1
            let prevPhoto = allPhotos[prevIndex]
            prevPhoto.isVisible = true // Mark as visible for memory manager
            
            // Access thumbnail to trigger load but in a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                _ = prevPhoto.thumbnail
            }
        }
        
        // Preload next photo if available
        if currentIndex < allPhotos.count - 1 {
            let nextIndex = currentIndex + 1
            let nextPhoto = allPhotos[nextIndex]
            nextPhoto.isVisible = true // Mark as visible for memory manager
            
            // Access thumbnail to trigger load but in a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                _ = nextPhoto.thumbnail
            }
        }
    }
    
    func navigateToPrevious() {
        if canGoToPrevious {
            // Clean up memory by releasing the full-size image of the current photo
            // but keep the thumbnail for the gallery view
            allPhotos[currentIndex].clearMemory(keepThumbnail: true)
            
            withAnimation {
                currentIndex -= 1
                // Reset rotation when changing photos
                imageRotation = 0
                // Reset zoom and pan
                resetZoomAndPan()
                // Clear face detection state
                isFaceDetectionActive = false
                detectedFaces = []
                modifiedImage = nil
            }
            
            // Preload adjacent photos for smoother navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.preloadAdjacentPhotos()
            }
        }
    }
    
    func navigateToNext() {
        if canGoToNext {
            // Clean up memory by releasing the full-size image of the current photo
            // but keep the thumbnail for the gallery view
            allPhotos[currentIndex].clearMemory(keepThumbnail: true)
            
            withAnimation {
                currentIndex += 1
                // Reset rotation when changing photos
                imageRotation = 0
                // Reset zoom and pan
                resetZoomAndPan()
                // Clear face detection state
                isFaceDetectionActive = false
                detectedFaces = []
                modifiedImage = nil
            }
            
            // Preload adjacent photos for smoother navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
        // Get the photo to delete
        let photoToDelete = currentPhoto
        
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
                            // If no photos left, call dismiss handler
                            if let onDismiss = self.onDismiss {
                                onDismiss()
                            }
                        } else {
                            // Adjust the current index if necessary
                            if self.currentIndex >= updatedPhotos.count {
                                self.currentIndex = updatedPhotos.count - 1
                            }
                            
                            // Update our photos array
                            self.allPhotos = updatedPhotos
                        }
                    } else {
                        // Single photo case, call dismiss handler
                        if let onDismiss = self.onDismiss {
                            onDismiss()
                        }
                    }
                }
            } catch {
                print("Error deleting photo: \(error.localizedDescription)")
                
                // Show error alert if needed - would be implemented with a published property
                DispatchQueue.main.async {
                    // Here you could set an error state and show an alert
                }
            }
        }
    }
    
    // MARK: - Sharing
    
    func sharePhoto(from viewController: UIViewController) {
        // Get the current photo image
        let image = displayedImage
        
        // Create a UIActivityViewController to show the sharing options
        let activityViewController = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        // For iPad support
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(x: viewController.view.bounds.midX, y: viewController.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        
        // Present the share sheet
        viewController.present(activityViewController, animated: true, completion: nil)
    }
    
    // MARK: - View Lifecycle
    
    func onAppear() {
        // When the detail view appears, ensure it's properly registered with memory manager
        if !allPhotos.isEmpty {
            // Current photo should be visible
            allPhotos[currentIndex].isVisible = true
            
            // Register all photos with the memory manager
            MemoryManager.shared.registerPhotos(allPhotos)
            
            // Preload adjacent photos for smoother navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.preloadAdjacentPhotos()
            }
        } else if let photo = photo {
            // Single photo case
            photo.isVisible = true
            MemoryManager.shared.registerPhotos([photo])
        }
    }
    
    func onDisappear() {
        // Clean up when view disappears
        if let onDismiss = onDismiss {
            onDismiss()
        }
    }
}
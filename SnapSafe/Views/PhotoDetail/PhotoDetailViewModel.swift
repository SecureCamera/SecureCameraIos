//
//  PhotoDetailViewModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import UIKit
import SwiftUI

class PhotoDetailViewModel: ObservableObject {
    private var photo: SecurePhoto?
    
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
    
    @Published var showImageInfo = false
    
    @Published var imageFrameSize: CGSize = .zero
    
    private let faceDetector = FaceDetector()
    private let secureFileManager = SecureFileManager()
    
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
    var currentPhoto: SecurePhoto {
        if !allPhotos.isEmpty {
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
    
    var displayedImage: UIImage {
        if isFaceDetectionActive, let modified = modifiedImage {
            return modified
        } else {
            let image = currentPhoto.fullImage
            DispatchQueue.main.async {
                MemoryManager.shared.checkMemoryUsage()
            }
            return image
        }
    }
    
    var canGoToPrevious: Bool {
        !allPhotos.isEmpty && currentIndex > 0
    }
    
    var canGoToNext: Bool {
        !allPhotos.isEmpty && currentIndex < allPhotos.count - 1
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
        withAnimation {
            isFaceDetectionActive = true
            processingFaces = true
        }
        
        detectedFaces = []
        modifiedImage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let imageToProcess = self.currentPhoto.fullImage
                
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
    }
    
    func toggleFaceSelection(_ face: DetectedFace) {
        if let index = detectedFaces.firstIndex(where: { $0.id == face.id }) {
            let updatedFaces = detectedFaces
            updatedFaces[index].isSelected.toggle()
            detectedFaces = updatedFaces
        }
    }
    
    func applyFaceMasking() {
        withAnimation {
            processingFaces = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
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
                        _ = try self.secureFileManager.savePhoto(imageData, withMetadata: metadataCopy)
                        
                        DispatchQueue.main.async {
                            withAnimation {
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
        print("deleteCurrentPhoto called - starting deletion process")
        // Get the photo to delete
        let photoToDelete = currentPhoto
        
        // Perform file deletion in a background thread
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Actually delete the file
                print("Attempting to delete file: \(photoToDelete.filename)")
                try self.secureFileManager.deletePhoto(filename: photoToDelete.filename)
                print("File deletion successful")
                
                // All UI updates must happen on the main thread
                DispatchQueue.main.async {
                    print("Calling onDelete callback")
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
                
                // Present the share sheet
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
            
            DispatchQueue.main.async {
                currentController.present(activityViewController, animated: true) {
                    print("Share sheet presented successfully (image fallback)")
                }
            }
        }
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

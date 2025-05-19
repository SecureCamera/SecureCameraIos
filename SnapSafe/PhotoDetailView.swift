//
//  PhotoDetailView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import SwiftUI
import ImageIO
import CoreGraphics

// Photo detail view that supports swiping between photos
struct PhotoDetailView: View {
    // For single photo case (fallback)
    var photo: SecurePhoto? = nil
    
    // For multiple photos case
    @State private var allPhotos: [SecurePhoto] = []
    var initialIndex: Int = 0
    
    let showFaceDetection: Bool
    var onDelete: ((SecurePhoto) -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    
    @State private var currentIndex: Int = 0
    @State private var showDeleteConfirmation = false
    @State private var imageRotation: Double = 0
    @State private var offset: CGFloat = 0
    @State private var isSwiping: Bool = false
    
    // Zoom and pan states
    @State private var currentScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var isZoomed: Bool = false
    @State private var lastDragPosition: CGSize = .zero // Keep track of last position
    
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
    init(photo: SecurePhoto, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.photo = photo
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self._allPhotos = State(initialValue: allPhotos)
        self.initialIndex = initialIndex
        self._currentIndex = State(initialValue: initialIndex)
        self.showFaceDetection = showFaceDetection
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    // Get the current photo to display
    private var currentPhoto: SecurePhoto {
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
    private var displayedImage: UIImage {
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
                            .opacity(isZoomed ? 0.5 : 1.0) // Fade when zoomed
                    }
                    
                    Spacer()
                    
                    // Zoom level indicator (only show when actively zooming)
                    if isZoomed {
                        ZStack {
                            Capsule()
                                .fill(Color.black.opacity(0.7))
                                .frame(width: 70, height: 30)
                            
                            Text(String(format: "%.1fx", currentScale))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .opacity(currentScale != 1.0 ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.2), value: currentScale)
                        .padding(.bottom, 10)
                    }
                    
                    // Centered image display
                    ZStack {
                        // Image display
                        Image(uiImage: displayedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .rotationEffect(.degrees(imageRotation))
                            .scaleEffect(currentScale)
                            .offset(x: offset + dragOffset.width, y: dragOffset.height)
                            .animation(.interactiveSpring(), value: offset) // Smooth animation for offset
                            .animation(nil, value: dragOffset) // No animation for drag to prevent jumping
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
                            // Apply multiple gestures with a gesture modifier
                            .gesture(
                                // Magnification (pinch) gesture for zoom in/out
                                MagnificationGesture()
                                    .onChanged { value in
                                        let delta = value / lastScale
                                        lastScale = value
                                        
                                        // Apply zoom with a smoothing factor
                                        let newScale = currentScale * delta
                                        // Limit the scale to reasonable bounds
                                        currentScale = min(max(newScale, 0.5), 6.0)
                                        
                                        // Update zoomed state for UI adjustments
                                        isZoomed = currentScale > 1.1
                                    }
                                    .onEnded { value in
                                        // Reset lastScale for next gesture
                                        lastScale = 1.0
                                        
                                        // Check if we should return to the gallery
                                        if currentScale < 0.6 && !isFaceDetectionActive {
                                            // User has pinched out enough to dismiss
                                            // Call cleanup handler before dismissing
                                            onDismiss?()
                                            dismiss()
                                        } else if currentScale < 1.0 {
                                            // Reset to normal scale using our helper method
                                            resetZoomAndPan()
                                        }
                                    }
                            )
                            // Add a drag gesture only when zoomed
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { gesture in
                                        if isZoomed {
                                            // When zoomed, add the new translation to the last drag position
                                            // This creates a cumulative drag effect
                                            self.dragOffset = CGSize(
                                                width: lastDragPosition.width + gesture.translation.width,
                                                height: lastDragPosition.height + gesture.translation.height
                                            )
                                        } else if !allPhotos.isEmpty && !isFaceDetectionActive {
                                            // Handle photo navigation swipe when not zoomed
                                            isSwiping = true
                                            offset = gesture.translation.width
                                        }
                                    }
                                    .onEnded { gesture in
                                        if isZoomed {
                                            // Calculate the final position including constraints
                                            let maxDragDistance = imageFrameSize.width * currentScale / 2
                                            let constrainedOffset = CGSize(
                                                width: max(-maxDragDistance, min(maxDragDistance, dragOffset.width)),
                                                height: max(-maxDragDistance, min(maxDragDistance, dragOffset.height))
                                            )
                                            
                                            // Update dragOffset with the constrained value
                                            self.dragOffset = constrainedOffset
                                            
                                            // Save this position as the new reference point for the next drag
                                            self.lastDragPosition = constrainedOffset
                                        } else if !isFaceDetectionActive {
                                            // When not zoomed, handle photo navigation
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
                            // Add a double tap gesture to toggle zoom
                            .onTapGesture(count: 2) {
                                if currentScale > 1.0 {
                                    // Reset zoom if zoomed in
                                    resetZoomAndPan()
                                } else {
                                    // Zoom in if not zoomed
                                    withAnimation(.spring()) {
                                        currentScale = 2.5
                                        isZoomed = true
                                    }
                                }
                            }
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
                        // Bottom toolbar with action buttons - hide when zoomed
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
                        .opacity(isZoomed ? 0 : 1) // Hide controls when zoomed
                        .animation(.easeInOut(duration: 0.2), value: isZoomed)
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
            .onDisappear {
                // Clean up when view disappears 
                onDismiss?()
            }
            .actionSheet(isPresented: $showMaskOptions) {
                ActionSheet(
                    title: Text("Select Mask Type"),
                    message: Text("Choose how to mask the selected faces"),
                    buttons: [
                        .default(Text("Blur")) {
                            selectedMaskMode = .blur
                            showBlurConfirmation = true
                        },
                        .default(Text("Pixelate")) {
                            selectedMaskMode = .pixelate
                            showBlurConfirmation = true
                        },
                        .default(Text("Blackout")) {
                            selectedMaskMode = .blackout
                            showBlurConfirmation = true
                        },
                        .default(Text("Noise")) {
                            selectedMaskMode = .noise
                            showBlurConfirmation = true
                        },
                        .cancel()
                    ]
                )
            }
            .onAppear {
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
            .onDisappear {
                // Explicit cleanup when view disappears
                if let onDismiss = onDismiss {
                    onDismiss()
                }
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
            // Use autoreleasepool to ensure memory is released promptly after processing
            autoreleasepool {
                let imageToProcess = currentPhoto.fullImage
                
                faceDetector.detectFaces(in: imageToProcess) { faces in
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
            // Use autoreleasepool to ensure memory is released promptly
            autoreleasepool {
                // Get the image to process, copy of metadata and selected mode
                let imageToProcess = currentPhoto.fullImage
                let facesToMask = detectedFaces
                let metadataCopy = currentPhoto.metadata
                let maskMode = selectedMaskMode
                
                // Process the image
                if let maskedImage = faceDetector.maskFaces(in: imageToProcess, faces: facesToMask, modes: [maskMode]) {
                    // Save the masked image to the file system
                    guard let imageData = maskedImage.jpegData(compressionQuality: 0.9) else {
                        DispatchQueue.main.async {
                            self.processingFaces = false
                        }
                        print("Error creating JPEG data")
                        return
                    }
                    
                    do {
                        try secureFileManager.savePhoto(imageData, withMetadata: metadataCopy)
                        
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
    
    // Preload adjacent photos to make swiping smoother
    func preloadAdjacentPhotos() {
        guard !allPhotos.isEmpty else { return }
        
        // Preload previous photo if available
        if currentIndex > 0 {
            let prevIndex = currentIndex - 1
            let prevPhoto = allPhotos[prevIndex]
            prevPhoto.isVisible = true  // Mark as visible for memory manager
            
            // Access thumbnail to trigger load but in a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                _ = prevPhoto.thumbnail
            }
        }
        
        // Preload next photo if available
        if currentIndex < allPhotos.count - 1 {
            let nextIndex = currentIndex + 1
            let nextPhoto = allPhotos[nextIndex]
            nextPhoto.isVisible = true  // Mark as visible for memory manager
            
            // Access thumbnail to trigger load but in a background thread
            DispatchQueue.global(qos: .userInitiated).async {
                _ = nextPhoto.thumbnail
            }
        }
    }
    
    // Navigation functions
    private func navigateToPrevious() {
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
    
    private func navigateToNext() {
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
    
    // Reset zoom and pan state to defaults
    private func resetZoomAndPan() {
        withAnimation(.spring()) {
            currentScale = 1.0
            dragOffset = .zero
            lastScale = 1.0
            isZoomed = false
        }
        // Reset the last drag position outside of animation to avoid jumps
        lastDragPosition = .zero
    }
    
    // Manually rotate image if needed
    private func rotateImage(direction: Double) {
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
            if let gpsData = metadata[String(kCGImagePropertyGPSDictionary)] as? [String: Any] {
                var locationParts: [String] = []
                
                // Extract latitude
                if let latitudeRef = gpsData[String(kCGImagePropertyGPSLatitudeRef)] as? String,
                   let latitude = gpsData[String(kCGImagePropertyGPSLatitude)] as? Double {
                    let latDirection = latitudeRef == "N" ? "N" : "S"
                    locationParts.append(String(format: "%.6f°%@", latitude, latDirection))
                }
                
                // Extract longitude
                if let longitudeRef = gpsData[String(kCGImagePropertyGPSLongitudeRef)] as? String,
                   let longitude = gpsData[String(kCGImagePropertyGPSLongitude)] as? Double {
                    let longDirection = longitudeRef == "E" ? "E" : "W"
                    locationParts.append(String(format: "%.6f°%@", longitude, longDirection))
                }
                
                // Include altitude if available
                if let altitude = gpsData[String(kCGImagePropertyGPSAltitude)] as? Double {
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
                        
                        if let exifDict = photo.metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any],
                           let dateTimeOriginal = exifDict[String(kCGImagePropertyExifDateTimeOriginal)] as? String {
                            HStack {
                                Text("Original Date")
                                Spacer()
                                Text(dateTimeOriginal)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Section(header: Text("Orientation")) {
                        if let tiffDict = photo.metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any],
                           let orientation = tiffDict[String(kCGImagePropertyTIFFOrientation)] as? Int {
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
                        if let exifDict = photo.metadata[String(kCGImagePropertyExifDictionary)] as? [String: Any] {
                            if let make = (photo.metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any])?[String(kCGImagePropertyTIFFMake)] as? String,
                               let model = (photo.metadata[String(kCGImagePropertyTIFFDictionary)] as? [String: Any])?[String(kCGImagePropertyTIFFModel)] as? String {
                                HStack {
                                    Text("Camera")
                                    Spacer()
                                    Text("\(make) \(model)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let fNumber = exifDict[String(kCGImagePropertyExifFNumber)] as? Double {
                                HStack {
                                    Text("Aperture")
                                    Spacer()
                                    Text(String(format: "f/%.1f", fNumber))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let exposureTime = exifDict[String(kCGImagePropertyExifExposureTime)] as? Double {
                                HStack {
                                    Text("Shutter Speed")
                                    Spacer()
                                    Text("\(exposureTime < 1 ? "1/\(Int(1/exposureTime))" : String(format: "%.1f", exposureTime))s")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let isoValue = exifDict[String(kCGImagePropertyExifISOSpeedRatings)] as? [Int],
                               let iso = isoValue.first {
                                HStack {
                                    Text("ISO")
                                    Spacer()
                                    Text("\(iso)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let focalLength = exifDict[String(kCGImagePropertyExifFocalLength)] as? Double {
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

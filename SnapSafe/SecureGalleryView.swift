//
//  SecureGalleryView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import PhotosUI
import SwiftUI

// Empty state view when no photos exist
struct EmptyGalleryView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Text("No photos yet")
                .font(.title)
                .foregroundColor(.secondary)
        }
    }
}

// Gallery toolbar view
struct GalleryToolbar: ToolbarContent {
    @Binding var isSelecting: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var selectedPhotoIds: Set<UUID>
    let hasSelection: Bool
    let onRefresh: () -> Void
    let onShare: () -> Void

    var body: some ToolbarContent {
        // Left side button (Select/Cancel)
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                if isSelecting {
                    // If we're currently selecting, cancel selection mode and clear selections
                    isSelecting = false
                    selectedPhotoIds.removeAll()
                } else {
                    // Enter selection mode
                    isSelecting = true
                }
            }) {
                Text(isSelecting ? "Cancel" : "Select")
                    .foregroundColor(isSelecting ? .red : .blue)
            }
        }

        // Right side buttons (delete/share when selecting, refresh/import otherwise)
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 20) {
                // When in selection mode and items are selected, show delete button
                if isSelecting && hasSelection {
                    // Delete button
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }

                    // Share button
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                }
                // When not in selection mode or nothing selected, show refresh button
                else if !isSelecting {
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
}

// Gallery view to display the stored photos
struct SecureGalleryView: View {
    @State private var photos: [SecurePhoto] = []
    @State private var selectedPhoto: SecurePhoto?
    @AppStorage("showFaceDetection") private var showFaceDetection = true // Using AppStorage to share with Settings
    @State private var isSelecting: Bool = false
    @State private var selectedPhotoIds = Set<UUID>()
    @State private var showDeleteConfirmation = false
    @State private var isShowingImagePicker = false
    @State private var importedImage: UIImage? // Legacy support
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting: Bool = false
    @State private var importProgress: Float = 0

    // Decoy selection mode
    @State private var isSelectingDecoys: Bool = false
    @State private var maxDecoys: Int = 5
    @State private var showDecoyLimitWarning: Bool = false
    @State private var showDecoyConfirmation: Bool = false

    private let secureFileManager = SecureFileManager()
    @Environment(\.dismiss) private var dismiss

    // Initializers
    init() {
        // Default initializer
    }

    // Initializer for decoy selection mode
    init(selectingDecoys: Bool) {
        _isSelectingDecoys = State(initialValue: selectingDecoys)
    }

    // Computed properties to simplify the view
    private var hasSelection: Bool {
        !selectedPhotoIds.isEmpty
    }

    // Computed property to get current decoy photo count
    private var currentDecoyCount: Int {
        photos.filter { $0.isDecoy }.count
    }

    // Get an array of selected photos for sharing
    private var selectedPhotos: [UIImage] {
        photos
            .filter { selectedPhotoIds.contains($0.id) }
            .map { $0.fullImage }
    }

    var body: some View {
//        VStack {
//        }
        NavigationView {
            ZStack {
                Group {
                    if photos.isEmpty {
                        EmptyGalleryView(onDismiss: { dismiss() })
                    } else {
                        photosGridView
                    }
                }

                // Import progress overlay
                if isImporting {
                    VStack {
                        ProgressView("Importing photos...", value: importProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding()

                        Text("\(Int(importProgress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 200)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemBackground))
                            .shadow(radius: 5)
                    )
                }
            }
            .navigationTitle(isSelectingDecoys ? "Select Decoy Photos" : "Secure Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Left side button differs based on mode
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectingDecoys {
                        // Cancel button for decoy selection mode
                        Button("Cancel") {
                            // Exit decoy selection mode and return to settings
                            isSelectingDecoys = false
                            isSelecting = false
                            selectedPhotoIds.removeAll()
                            dismiss()
                        }
                        .foregroundColor(.red)
                    } else if isSelecting {
                        // Cancel button for normal selection mode
                        Button("Cancel") {
                            isSelecting = false
                            selectedPhotoIds.removeAll()
                        }
                        .foregroundColor(.red)
                    } else {
                        // Select button for normal mode
                        Button("Select") {
                            isSelecting = true
                        }
                        .foregroundColor(.blue)
                    }
                }

                // Right side actions
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Show Save button when in decoy selection mode
                        if isSelectingDecoys {
                            // Save button for decoy selection
                            Button("Save") {
                                if selectedPhotoIds.count > maxDecoys {
                                    // Show warning if too many decoys selected
                                    showDecoyLimitWarning = true
                                } else {
                                    // Show confirmation before saving
                                    showDecoyConfirmation = true
                                }
                            }
                            .foregroundColor(.blue)
                            .disabled(selectedPhotoIds.isEmpty)

                            // Count label showing selected/max
                            Text("\(selectedPhotoIds.count)/\(maxDecoys)")
                                .font(.caption)
                                .foregroundColor(selectedPhotoIds.count > maxDecoys ? .red : .secondary)
                                .frame(minWidth: 40)
                        }
                        // Show import button when not in selection mode
                        else if !isSelecting {
                            // Import button
                            PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 16))
                            }
                            .onChange(of: pickerItems) { _, newItems in
                                // Process selected images from picker
                                Task {
                                    var hadSuccessfulImport = false

                                    // Show import progress to user
                                    let importCount = newItems.count
                                    if importCount > 0 {
                                        // Update UI to show import is happening
                                        await MainActor.run {
                                            isImporting = true
                                            importProgress = 0
                                        }

                                        print("Importing \(importCount) photos...")

                                        // Process each selected item with progress tracking
                                        for (index, item) in newItems.enumerated() {
                                            // Update progress
                                            let currentProgress = Float(index) / Float(importCount)
                                            await MainActor.run {
                                                importProgress = currentProgress
                                            }

                                            // Load and process the image
                                            if let data = try? await item.loadTransferable(type: Data.self) {
                                                // Process this image
                                                await processImportedImageData(data)
                                                hadSuccessfulImport = true
                                            }
                                        }

                                        // Show 100% progress briefly before hiding
                                        await MainActor.run {
                                            importProgress = 1.0
                                        }

                                        // Small delay to show completion
                                        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                                    }

                                    // After importing all items, reset the picker selection and refresh gallery
                                    await MainActor.run {
                                        // Reset picked items
                                        pickerItems = []

                                        // Hide progress indicator
                                        isImporting = false

                                        // Reload the gallery if we imported images
                                        if hadSuccessfulImport {
                                            loadPhotos()
                                        }
                                    }
                                }
                            }

                            // Refresh button
                            Button(action: loadPhotos) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.blue)
                            }
                        }
                        // When in normal selection mode and items are selected
                        else if hasSelection && !isSelectingDecoys {
                            // Delete button
                            Button(action: { 
                                print("Delete button pressed in gallery view, selected photos: \(selectedPhotoIds.count)")
                                showDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }

                            // Share button
                            Button(action: shareSelectedPhotos) {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .onAppear(perform: loadPhotos)
            .onChange(of: selectedPhoto) { _, newValue in
                if newValue == nil {
                    loadPhotos()
                }
            }
//            .sheet(isPresented: $isShowingImagePicker) {
            //// old way
            ////                ImagePicker(image: $importedImage, onDismiss: handleImportedImage)
//                EmptyView()
//            }
            .sheet(item: $selectedPhoto) { photo in
                // Find the index of the selected photo in the photos array
                if let initialIndex = photos.firstIndex(where: { $0.id == photo.id }) {
                    PhotoDetailView(
                        allPhotos: photos,
                        initialIndex: initialIndex,
                        showFaceDetection: showFaceDetection,
                        onDelete: { _ in loadPhotos() },
                        onDismiss: {
                            // Clean up memory for all loaded full-size images when returning to gallery
                            for photo in self.photos {
                                photo.clearMemory(keepThumbnail: true)
                            }
                            // Trigger garbage collection
                            MemoryManager.shared.checkMemoryUsage()
                        }
                    )
                    .onAppear {
                        // Trigger preloading of adjacent photos after a small delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // We can only preload by ensuring the photos are registered with memory manager
                            MemoryManager.shared.registerPhotos(photos)

                            // This will cause adjacent photos to be preloaded
                            if initialIndex > 0 {
                                photos[initialIndex - 1].isVisible = true
                            }
                            if initialIndex < photos.count - 1 {
                                photos[initialIndex + 1].isVisible = true
                            }
                        }
                    }
                } else {
                    // Fallback if photo not found in array
                    PhotoDetailView(
                        photo: photo,
                        showFaceDetection: showFaceDetection,
                        onDelete: { _ in loadPhotos() },
                        onDismiss: {
                            photo.clearMemory(keepThumbnail: true)
                            // Trigger garbage collection
                            MemoryManager.shared.checkMemoryUsage()
                        }
                    )
                }
            }
            .alert(
                "Delete Photo\(selectedPhotoIds.count > 1 ? "s" : "")",
                isPresented: $showDeleteConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        print("Delete confirmation button pressed, deleting \(selectedPhotoIds.count) photos")
                        deleteSelectedPhotos()
                    }
                },
                message: {
                    Text("Are you sure you want to delete \(selectedPhotoIds.count) photo\(selectedPhotoIds.count > 1 ? "s" : "")? This action cannot be undone.")
                }
            )
            .alert(
                "Too Many Decoys",
                isPresented: $showDecoyLimitWarning,
                actions: {
                    Button("OK", role: .cancel) {}
                },
                message: {
                    Text("You can select a maximum of \(maxDecoys) decoy photos. Please deselect some photos before saving.")
                }
            )
            .alert(
                "Save Decoy Selection",
                isPresented: $showDecoyConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {}
                    Button("Save") {
                        saveDecoySelections()
                    }
                },
                message: {
                    Text("Are you sure you want to save these \(selectedPhotoIds.count) photos as decoys? These will be shown when the emergency PIN is entered.")
                }
            )
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
                        isSelecting: isSelecting,
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

    // Process image data from the PhotosPicker and save it to the gallery
    private func processImportedImageData(_ imageData: Data) async {
        // Create metadata including import timestamp
        let metadata: [String: Any] = [
            "imported": true,
            "importSource": "PhotosPicker",
            "creationDate": Date().timeIntervalSince1970,
        ]

        // Save the photo data (runs on background thread)
        let filename = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let filename = try self.secureFileManager.savePhoto(imageData, withMetadata: metadata)
                    continuation.resume(returning: filename)
                } catch {
                    print("Error saving imported photo: \(error.localizedDescription)")
                    continuation.resume(returning: "")
                }
            }
        }

        if !filename.isEmpty {
            print("Successfully imported photo: \(filename)")
        }
    }

    // Legacy method for backward compatibility
    private func handleImportedImage() {
        guard let image = importedImage else { return }

        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("Failed to convert image to data")
            return
        }

        // Process the image data using the new method
        Task {
            await processImportedImageData(imageData)

            // Reload photos to show the new one
            DispatchQueue.main.async {
                self.importedImage = nil
                self.loadPhotos()
            }
        }
    }

    // }

    // MARK: - Action methods

    private func handlePhotoTap(_ photo: SecurePhoto) {
        if isSelecting {
            togglePhotoSelection(photo)
        } else {
            selectedPhoto = photo
        }
    }

    private func togglePhotoSelection(_ photo: SecurePhoto) {
        if selectedPhotoIds.contains(photo.id) {
            selectedPhotoIds.remove(photo.id)
        } else {
            // If we're selecting decoys and already at the limit, don't allow more selections
            if isSelectingDecoys && selectedPhotoIds.count >= maxDecoys {
                showDecoyLimitWarning = true
                return
            }
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
                // Only load metadata and file URLs, not actual image data
                let photoMetadata = try self.secureFileManager.loadAllPhotoMetadata()

                // Create photo objects that will load their images on demand
                var loadedPhotos = photoMetadata.map { filename, metadata, fileURL in
                    SecurePhoto(
                        filename: filename,
                        metadata: metadata,
                        fileURL: fileURL
                    )
                }

                // We'll update on main thread after sorting

                // Sort photos by creation date (oldest at top, newest at bottom)
                loadedPhotos.sort { photo1, photo2 in
                    // Get creation dates from metadata
                    let date1 = photo1.metadata["creationDate"] as? Double ?? 0
                    let date2 = photo2.metadata["creationDate"] as? Double ?? 0

                    // Sort by date (descending - newest first, which is more typical for photo galleries)
                    return date2 < date1
                }

                // Update UI on the main thread
                DispatchQueue.main.async {
                    // First clear memory of existing photos if we're refreshing
                    MemoryManager.shared.freeAllMemory()

                    // Update the photos array
                    self.photos = loadedPhotos

                    // If in decoy selection mode, pre-select existing decoy photos
                    if self.isSelectingDecoys {
                        // Find and select all photos that are already marked as decoys
                        for photo in loadedPhotos {
                            if photo.isDecoy {
                                self.selectedPhotoIds.insert(photo.id)
                            }
                        }

                        // Enable selection mode
                        self.isSelecting = true
                    }

                    // Register these photos with the memory manager
                    MemoryManager.shared.registerPhotos(loadedPhotos)
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
        print("deleteSelectedPhotos() called")
        
        // Create a local copy of the photos to delete
        let photosToDelete = selectedPhotoIds.compactMap { id in
            photos.first(where: { $0.id == id })
        }
        
        print("Will delete \(photosToDelete.count) photos: \(photosToDelete.map { $0.filename }.joined(separator: ", "))")

        // Clear selection and exit selection mode immediately
        // for better UI responsiveness
        DispatchQueue.main.async {
            print("Clearing selection UI state")
            self.selectedPhotoIds.removeAll()
            self.isSelecting = false
        }

        // Process deletions in a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            print("Starting background deletion process")
            let group = DispatchGroup()

            // Delete each photo
            for photo in photosToDelete {
                group.enter()
                do {
                    print("Attempting to delete: \(photo.filename)")
                    try self.secureFileManager.deletePhoto(filename: photo.filename)
                    print("Successfully deleted: \(photo.filename)")
                    group.leave()
                } catch {
                    print("Error deleting photo \(photo.filename): \(error.localizedDescription)")
                    group.leave()
                }
            }

            // After all deletions are complete, update the UI
            group.notify(queue: .main) {
                print("All deletions complete, updating UI")
                
                // Count photos before removal
                let initialCount = self.photos.count
                
                // Remove deleted photos from our array
                withAnimation {
                    self.photos.removeAll { photo in
                        let shouldRemove = photosToDelete.contains { $0.id == photo.id }
                        if shouldRemove {
                            print("Removing photo \(photo.filename) from UI")
                        }
                        return shouldRemove
                    }
                }
                
                // Verify removal
                let finalCount = self.photos.count
                let removedCount = initialCount - finalCount
                print("UI update complete: removed \(removedCount) photos. Gallery now has \(finalCount) photos.")
            }
        }
    }

    // Share selected photos
    // Save selected photos as decoys
    private func saveDecoySelections() {
        // First, un-mark any previously tagged decoys that aren't currently selected
        for photo in photos {
            let isCurrentlySelected = selectedPhotoIds.contains(photo.id)

            // If it's currently a decoy but not selected, unmark it
            if photo.isDecoy && !isCurrentlySelected {
                photo.setDecoyStatus(false)
            }
            // If it's selected but not a decoy, mark it
            else if isCurrentlySelected && !photo.isDecoy {
                photo.setDecoyStatus(true)
            }
        }

        // Reset selection and exit decoy mode
        isSelectingDecoys = false
        isSelecting = false
        selectedPhotoIds.removeAll()

        // Return to settings
        dismiss()
    }


    private func shareSelectedPhotos() {
        // Get all the selected photos
        let images = selectedPhotos

        guard !images.isEmpty else { return }

        // Use UIApplication.shared.windows approach for SwiftUI integration
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController
        else {
            print("Could not find root view controller")
            return
        }

        // Create a UIActivityViewController to show the sharing options
        let activityViewController = UIActivityViewController(
            activityItems: images,
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
}

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

// Gallery view to display the stored photos
struct SecureGalleryView: View {
    @State private var photos: [SecurePhoto] = []
    @State private var selectedPhoto: SecurePhoto?
    @AppStorage("showFaceDetection") private var showFaceDetection = true // Using AppStorage to share with Settings
    @State private var isSelecting: Bool = false
    @State private var selectedPhotoIds = Set<String>()
    @State private var showDeleteConfirmation = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting: Bool = false
    @State private var importProgress: Float = 0


    // Decoy selection mode
    @State private var isSelectingDecoys: Bool = false
    @State private var maxDecoys: Int = 10
    @State private var showDecoyLimitWarning: Bool = false
    @State private var showDecoyConfirmation: Bool = false

    private let secureFileManager = SecureFileManager()
    @Environment(\.dismiss) private var dismiss

    // Callback for dismissing the gallery
    let onDismiss: (() -> Void)?

    // Initializers
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    // Initializer for decoy selection mode
    init(selectingDecoys: Bool, onDismiss: (() -> Void)? = nil) {
        _isSelectingDecoys = State(initialValue: selectingDecoys)
        self.onDismiss = onDismiss
    }

    // Computed properties to simplify the view
    private var hasSelection: Bool {
        !selectedPhotoIds.isEmpty
    }

    // Computed property to get current decoy photo count
//    private var currentDecoyCount: Int {
//        photos.count(where: { $0.isDecoy })
//    }

    // Get an array of selected photos for sharing
    private var selectedPhotos: [UIImage] {
        photos
            .filter { selectedPhotoIds.contains($0.id) }
            .map(\.fullImage)
    }

    var body: some View {
        ZStack {
            Group {
                if photos.isEmpty {
                    EmptyGalleryView(onDismiss: {
                        onDismiss?()
                        dismiss()
                    })
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button in the leading position
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if isSelectingDecoys {
                        // Exit decoy selection mode and return to settings
                        isSelectingDecoys = false
                        isSelecting = false
                        selectedPhotoIds.removeAll()
                    }
                    onDismiss?()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
            }

            // Action buttons in the trailing position (simplified for top toolbar)
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isSelectingDecoys {
                        // Count label and Save button for decoy selection
                        Text("\(selectedPhotoIds.count)/\(maxDecoys)")
                            .font(.caption)
                            .foregroundColor(selectedPhotoIds.count > maxDecoys ? .red : .secondary)

                        Button("Save") {
                            if selectedPhotoIds.count > maxDecoys {
                                showDecoyLimitWarning = true
                            } else {
                                showDecoyConfirmation = true
                            }
                        }
                        .foregroundColor(.blue)
                        .disabled(selectedPhotoIds.isEmpty)
                    } else if isSelecting {
                        // Cancel selection button
                        Button("Cancel") {
                            isSelecting = false
                            selectedPhotoIds.removeAll()
                        }
                        .foregroundColor(.red)
                    } else {
                        // Context menu with Select and Filter options
                        Menu {
                            Button("Select Photos") {
                                isSelecting = true
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .toolbar {
            // Bottom toolbar with main action buttons
            ToolbarItemGroup(placement: .bottomBar) {
                if !isSelectingDecoys, !isSelecting {
                    // Normal mode: Import and Refresh buttons
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Label("Import", systemImage: "square.and.arrow.down")
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

                    Spacer()

//                    Button(action: loadPhotos) {
//                        Label("Refresh", systemImage: "arrow.clockwise")
//                    }
                } else if isSelecting, hasSelection, !isSelectingDecoys {
                    // Selection mode: Delete and Share buttons
                    Button(action: {
                        print("Delete button pressed in gallery view, selected photos: \(selectedPhotoIds.count)")
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }

                    Spacer()

                    Button(action: shareSelectedPhotos) {
                        Label("Share", systemImage: "square.and.arrow.up")
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
        .fullScreenCover(item: $selectedPhoto) { photo in
            // Find the index of the selected photo in the photos array
            if let initialIndex = photos.firstIndex(where: { $0.id == photo.id }) {
                EnhancedPhotoDetailView(
                    allPhotos: photos,
                    initialIndex: initialIndex,
                    showFaceDetection: showFaceDetection,
                    onDelete: { _ in loadPhotos() },
                    onDismiss: {
                        // Clean up memory for all loaded full-size images when returning to gallery
                        for photo in photos {
                            photo.clearMemory(keepThumbnail: true)
                        }
                        // Trigger garbage collection
                        MemoryManager.shared.checkMemoryUsage()
                    }
                )
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
                    let filename = try secureFileManager.savePhoto(imageData, withMetadata: metadata)
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
//    private func handleImportedImage() {
//        guard let image = importedImage else { return }
//
//        // Convert image to data
//        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
//            print("Failed to convert image to data")
//            return
//        }
//
//        // Process the image data using the new method
//        Task {
//            await processImportedImageData(imageData)
//
//            // Reload photos to show the new one
//            DispatchQueue.main.async {
//                importedImage = nil
//                loadPhotos()
//            }
//        }
//    }

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
            if isSelectingDecoys, selectedPhotoIds.count >= maxDecoys {
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
//    private func fixImageOrientation(_ image: UIImage) -> UIImage {
//        // If the orientation is already correct, return the image as is
//        if image.imageOrientation == .up {
//            return image
//        }
//
//        // Create a new CGContext with proper orientation
//        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
//        image.draw(in: CGRect(origin: .zero, size: image.size))
//        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
//        UIGraphicsEndImageContext()
//
//        return normalizedImage
//    }

    private func loadPhotos() {
        // Load photos in the background thread to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Load metadata and file URLs from legacy system
                let photoMetadata = try secureFileManager.loadAllPhotoMetadata()

                // Convert legacy metadata to SecurePhoto objects
                var loadedPhotos: [SecurePhoto] = []

                for (filename, metadataDict, fileURL) in photoMetadata {
                    do {
                        // Load the unencrypted photo data from legacy system
                        let imageData = try Data(contentsOf: fileURL)

                        // Convert legacy metadata dictionary to PhotoMetadata struct
                        let creationDate = Date(timeIntervalSince1970: metadataDict["creationDate"] as? TimeInterval ?? Date().timeIntervalSince1970)
                        let modificationDate = Date(timeIntervalSince1970: metadataDict["modificationDate"] as? TimeInterval ?? Date().timeIntervalSince1970)
                        let fileSize = metadataDict["fileSize"] as? Int ?? imageData.count
                        let isDecoy = metadataDict["isDecoy"] as? Bool ?? false

                        // Create PhotoMetadata struct
                        let metadata = PhotoMetadata(
                            id: filename,
                            creationDate: creationDate,
                            modificationDate: modificationDate,
                            fileSize: fileSize,
                            faces: [], // TODO: Load faces from metadata if available
                            maskMode: .none, // TODO: Load mask mode from metadata if available
                            isDecoy: isDecoy
                        )

                        // Create UIImage and generate thumbnail
                        guard let image = UIImage(data: imageData) else {
                            print("Invalid image data for \(filename)")
                            continue
                        }

                        // Generate thumbnail
                        let thumbnailSize = CGSize(width: 200, height: 200)
                        let renderer = UIGraphicsImageRenderer(size: thumbnailSize)
                        let thumbnail = renderer.image { _ in
                            image.draw(in: CGRect(origin: .zero, size: thumbnailSize))
                        }

                        // Create SecurePhoto object with cached images (legacy system uses unencrypted data)
                        let securePhoto = SecurePhoto(
                            id: filename,
                            encryptedData: Data(), // Empty since legacy system doesn't encrypt
                            metadata: metadata,
                            cachedImage: image,
                            cachedThumbnail: thumbnail
                        )

                        loadedPhotos.append(securePhoto)
                    } catch {
                        print("Error loading photo \(filename): \(error.localizedDescription)")
                    }
                }

                // Sort by creation date (newest first)
                loadedPhotos.sort { $0.metadata.creationDate > $1.metadata.creationDate }

                // Update UI on the main thread
                DispatchQueue.main.async {
                    // First clear memory of existing photos if we're refreshing
                    MemoryManager.shared.freeAllMemory()

                    // Update the photos array
                    photos = loadedPhotos

                    // If in decoy selection mode, pre-select existing decoy photos
                    if isSelectingDecoys {
                        // Find and select all photos that are already marked as decoys
                        for photo in loadedPhotos {
                            if photo.isDecoy {
                                selectedPhotoIds.insert(photo.id)
                            }
                        }

                        // Enable selection mode
                        isSelecting = true
                    }

                    // Register these photos with the memory manager
                    MemoryManager.shared.registerPhotos(loadedPhotos)
                }
            } catch {
                print("Error loading photos: \(error.localizedDescription)")
            }
        }
    }

//    private func deletePhoto(_ photo: SecurePhoto) {
//        // Perform file deletion in background thread
//        DispatchQueue.global(qos: .userInitiated).async {
//            do {
//                try secureFileManager.deletePhoto(filename: photo.id)
//
//                // Update UI on main thread
//                DispatchQueue.main.async {
//                    // Remove from the local array
//                    withAnimation {
//                        photos.removeAll { $0.id == photo.id }
//                        if selectedPhotoIds.contains(photo.id) {
//                            selectedPhotoIds.remove(photo.id)
//                        }
//                    }
//                }
//            } catch {
//                print("Error deleting photo: \(error.localizedDescription)")
//            }
//        }
//    }

    private func deleteSelectedPhotos() {
        print("deleteSelectedPhotos() called")

        // Create a local copy of the photos to delete
        let photosToDelete = selectedPhotoIds.compactMap { id in
            photos.first(where: { $0.id == id })
        }

        print("Will delete \(photosToDelete.count) photos: \(photosToDelete.map(\.id).joined(separator: ", "))")

        // Clear selection and exit selection mode immediately
        // for better UI responsiveness
        DispatchQueue.main.async {
            print("Clearing selection UI state")
            selectedPhotoIds.removeAll()
            isSelecting = false
        }

        // Process deletions in a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            print("Starting background deletion process")
            let group = DispatchGroup()

            // Delete each photo
            for photo in photosToDelete {
                group.enter()
                do {
                    print("Attempting to delete: \(photo.id)")
                    try secureFileManager.deletePhoto(filename: photo.id)
                    print("Successfully deleted: \(photo.id)")
                    group.leave()
                } catch {
                    print("Error deleting photo \(photo.id): \(error.localizedDescription)")
                    group.leave()
                }
            }

            // After all deletions are complete, update the UI
            group.notify(queue: .main) {
                print("All deletions complete, updating UI")

                // Count photos before removal
                let initialCount = photos.count

                // Remove deleted photos from our array
                withAnimation {
                    photos.removeAll { photo in
                        let shouldRemove = photosToDelete.contains { $0.id == photo.id }
                        if shouldRemove {
                            print("Removing photo \(photo.id) from UI")
                        }
                        return shouldRemove
                    }
                }

                // Verify removal
                let finalCount = photos.count
                let removedCount = initialCount - finalCount
                print("UI update complete: removed \(removedCount) photos. Gallery now has \(finalCount) photos.")
            }
        }
    }

    // Share selected photos
    // Save selected photos as decoys
    private func saveDecoySelections() {
        // First, un-mark any previously tagged decoys that aren't currently selected
//        for photo in photos {
//            let isCurrentlySelected = selectedPhotoIds.contains(photo.id)

        // TODO: Implement decoy status update with new repository pattern
        // if photo.isDecoy && !isCurrentlySelected {
        //     photo.setDecoyStatus(false)
        // }
        // else if isCurrentlySelected && !photo.isDecoy {
        //     photo.setDecoyStatus(true)
        // }
//        }

        // Reset selection and exit decoy mode
        isSelectingDecoys = false
        isSelecting = false
        selectedPhotoIds.removeAll()

        // Return to settings
        onDismiss?()
        dismiss()
    }

    private func shareSelectedPhotos() {
        // Get all the selected photos
        let images = selectedPhotos
        guard !images.isEmpty else { return }

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

        // Create and prepare temporary files with UUID filenames
        var filesToShare: [URL] = []

        for image in images {
            if let imageData = image.jpegData(compressionQuality: 0.9) {
                do {
                    let fileURL = try secureFileManager.preparePhotoForSharing(imageData: imageData)
                    filesToShare.append(fileURL)
                    print("Prepared file for sharing: \(fileURL.lastPathComponent)")
                } catch {
                    print("Error preparing photo for sharing: \(error.localizedDescription)")
                }
            }
        }

        // Share files if any were successfully prepared
        if !filesToShare.isEmpty {
            // Create a UIActivityViewController to share the files
            let activityViewController = UIActivityViewController(
                activityItems: filesToShare,
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
                    print("Share sheet presented successfully for \(filesToShare.count) files")
                }
            }
        } else {
            // Fallback to sharing just the images if file preparation failed for all
            print("Falling back to sharing images directly")

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

            DispatchQueue.main.async {
                currentController.present(activityViewController, animated: true, completion: nil)
            }
        }
    }
}

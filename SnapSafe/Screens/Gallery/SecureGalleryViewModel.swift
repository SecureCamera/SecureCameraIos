//
//  SecureGalleryViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import Foundation
import PhotosUI
import SwiftUI
import Combine
import FactoryKit

@MainActor
final class SecureGalleryViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var photos: [SecurePhoto] = []
    @Published var selectedPhoto: SecurePhoto?
    @Published var isSelecting: Bool = false
    @Published var selectedPhotoIds = Set<UUID>()
    @Published var showDeleteConfirmation = false
    @Published var isShowingImagePicker = false
    @Published var importedImage: UIImage?
    @Published var pickerItems: [PhotosPickerItem] = []
    @Published var isImporting: Bool = false
    @Published var importProgress: Float = 0
    
    // Decoy selection mode
    @Published var isSelectingDecoys: Bool = false
    @Published var maxDecoys: Int = 10
    @Published var showDecoyLimitWarning: Bool = false
    @Published var showDecoyConfirmation: Bool = false
    
    // MARK: - Dependencies
    
    private let secureFileManager = SecureFileManager()
    private var cancellables = Set<AnyCancellable>()
    
    @InjectedObject(\.securityOverlayViewModel) 
    private var securityViewModel: SecurityOverlayViewModel
    
    // Track currently presented activity controller for dismissal
    private weak var currentActivityController: UIActivityViewController?
    
    // MARK: - Initialization
    
    init(selectingDecoys: Bool = false) {
        self.isSelectingDecoys = selectingDecoys
        setupObservers()
    }
    
    // MARK: - Computed Properties
    
    var hasSelection: Bool {
        !selectedPhotoIds.isEmpty
    }
    
    var currentDecoyCount: Int {
        photos.filter { $0.isDecoy }.count
    }
    
    var selectedPhotos: [UIImage] {
        photos
            .filter { selectedPhotoIds.contains($0.id) }
            .map { $0.fullImage }
    }
    
    var navigationTitle: String {
        if isSelectingDecoys {
            return "Select Decoy Photos"
        } else {
            return "Secure Gallery"
        }
    }
    
    var decoyCountText: String {
        "\(selectedPhotoIds.count)/\(maxDecoys)"
    }
    
    var decoyCountTextColor: Color {
        selectedPhotoIds.count > maxDecoys ? .red : .secondary
    }
    
    var isSaveDecoyButtonDisabled: Bool {
        selectedPhotoIds.isEmpty
    }
    
    var deleteAlertTitle: String {
        "Delete Photo\(selectedPhotoIds.count > 1 ? "s" : "")"
    }
    
    var deleteAlertMessage: String {
        "Are you sure you want to delete \(selectedPhotoIds.count) photo\(selectedPhotoIds.count > 1 ? "s" : "")? This action cannot be undone."
    }
    
    var decoyConfirmationMessage: String {
        "Are you sure you want to save these \(selectedPhotoIds.count) photos as decoys? These will be shown when the emergency PIN is entered."
    }
    
    var decoyLimitWarningMessage: String {
        "You can select a maximum of \(maxDecoys) decoy photos. Please deselect some photos before saving."
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        loadPhotos()
    }
    
    func onSelectedPhotoChange(_ newValue: SecurePhoto?) {
        if newValue == nil {
            loadPhotos()
        }
    }
    
    func handlePhotoTap(_ photo: SecurePhoto) {
        if isSelecting {
            togglePhotoSelection(photo)
        } else {
            selectedPhoto = photo
        }
    }
    
    func togglePhotoSelection(_ photo: SecurePhoto) {
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
    
    func prepareToDeleteSinglePhoto(_ photo: SecurePhoto) {
        selectedPhotoIds = [photo.id]
        showDeleteConfirmation = true
    }
    
    func startSelecting() {
        isSelecting = true
    }
    
    func cancelSelecting() {
        isSelecting = false
        selectedPhotoIds.removeAll()
    }
    
    func exitDecoyMode() {
        isSelectingDecoys = false
        isSelecting = false
        selectedPhotoIds.removeAll()
    }
    
    func showDecoyLimitAlert() {
        showDecoyLimitWarning = true
    }
    
    func showDecoyConfirmationAlert() {
        if selectedPhotoIds.count > maxDecoys {
            showDecoyLimitWarning = true
        } else {
            showDecoyConfirmation = true
        }
    }
    
    func showDeleteAlert() {
        showDeleteConfirmation = true
    }
    
    func processPickerItems(_ newItems: [PhotosPickerItem]) {
        Task {
            var hadSuccessfulImport = false

            // Show import progress to user
            let importCount = newItems.count
            if importCount > 0 {
                // Update UI to show import is happening
                isImporting = true
                importProgress = 0

                print("Importing \(importCount) photos...")

                // Process each selected item with progress tracking
                for (index, item) in newItems.enumerated() {
                    // Update progress
                    let currentProgress = Float(index) / Float(importCount)
                    importProgress = currentProgress

                    // Load and process the image
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        // Process this image
                        await processImportedImageData(data)
                        hadSuccessfulImport = true
                    }
                }

                // Show 100% progress briefly before hiding
                importProgress = 1.0

                // Small delay to show completion
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            }

            // After importing all items, reset the picker selection and refresh gallery
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
    
    func deleteSelectedPhotos() {
        print("deleteSelectedPhotos() called")
        
        // Create a local copy of the photos to delete
        let photosToDelete = selectedPhotoIds.compactMap { id in
            photos.first(where: { $0.id == id })
        }
        
        print("Will delete \(photosToDelete.count) photos: \(photosToDelete.map { $0.filename }.joined(separator: ", "))")

        // Clear selection and exit selection mode immediately
        // for better UI responsiveness
        selectedPhotoIds.removeAll()
        isSelecting = false

        // Process deletions in a background queue
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            print("Starting background deletion process")

            // Delete each photo
            for photo in photosToDelete {
                do {
                    print("Attempting to delete: \(photo.filename)")
                    try await self.secureFileManager.deletePhoto(filename: photo.filename)
                    print("Successfully deleted: \(photo.filename)")
                } catch {
                    print("Error deleting photo \(photo.filename): \(error.localizedDescription)")
                }
            }

            // After all deletions are complete, update the UI
            await MainActor.run {
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
    
    func saveDecoySelections() {
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
    }
    
    func shareSelectedPhotos() {
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
            
            // Store reference and present the share sheet
            currentActivityController = activityViewController
            currentController.present(activityViewController, animated: true) {
                print("Share sheet presented successfully for \(filesToShare.count) files")
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
            
            // Store reference and present the share sheet
            currentActivityController = activityViewController
            currentController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    func clearMemoryForPhoto(_ photo: SecurePhoto) {
        photo.clearMemory(keepThumbnail: true)
        // Trigger garbage collection
        MemoryManager.shared.checkMemoryUsage()
    }
    
    func clearMemoryForAllPhotos() {
        // Clean up memory for all loaded full-size images when returning to gallery
        for photo in self.photos {
            photo.clearMemory(keepThumbnail: true)
        }
        // Trigger garbage collection
        MemoryManager.shared.checkMemoryUsage()
    }
    
    // MARK: - Private Methods
    
    private func dismissAllAlerts() {
        // Dismiss all active alert states
        showDeleteConfirmation = false
        showDecoyLimitWarning = false
        showDecoyConfirmation = false
        
        // Dismiss any currently presented activity controller (iOS export dialog)
        currentActivityController?.dismiss(animated: false, completion: nil)
        currentActivityController = nil
    }
    
    private func setupObservers() {
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
    
    private func loadPhotos() {
        // Load photos in the background thread to avoid UI blocking
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
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

                // Sort photos by creation date (oldest at top, newest at bottom)
                loadedPhotos.sort { photo1, photo2 in
                    // Get creation dates from metadata
                    let date1 = photo1.metadata["creationDate"] as? Double ?? 0
                    let date2 = photo2.metadata["creationDate"] as? Double ?? 0

                    // Sort by date (descending - newest first, which is more typical for photo galleries)
                    return date2 < date1
                }

                // Update UI on the main thread
                await MainActor.run {
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
    
    private func processImportedImageData(_ imageData: Data) async {
        // Create metadata including import timestamp
        let metadata: [String: Any] = [
            "imported": true,
            "importSource": "PhotosPicker",
            "creationDate": Date().timeIntervalSince1970,
        ]

        // Save the photo data (runs on background thread)
        let filename = await withCheckedContinuation { continuation in
            Task.detached {
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
            await MainActor.run {
                self.importedImage = nil
                self.loadPhotos()
            }
        }
    }
    
    private func deletePhoto(_ photo: SecurePhoto) {
        // Perform file deletion in background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            do {
                try await self.secureFileManager.deletePhoto(filename: photo.filename)

                // Update UI on main thread
                await MainActor.run {
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
}

// MARK: - Extensions for async support

extension SecureFileManager {
    func deletePhoto(filename: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.deletePhoto(filename: filename)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

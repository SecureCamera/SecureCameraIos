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
import Logging

@MainActor
final class SecureGalleryViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var photos: [PhotoDef] = []
    @Published var selectedPhoto: PhotoDef?
    @Published var isSelecting: Bool = false
    @Published var selectedPhotoIds = Set<PhotoDef>()
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
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.clock)
    private var clock: Clock
    
    @Injected(\.addDecoyPhotoUseCase)
    private var addDecoyPhotoUseCase: AddDecoyPhotoUseCase
    
    @Injected(\.prepareForSharingUseCase)
    private var prepareForSharingUseCase: PrepareForSharingUseCase
    
    @Injected(\.securityOverlayViewModel)
    private var securityViewModel: SecurityOverlayViewModel
    
    private var cancellables = Set<AnyCancellable>()
    
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
        photos.filter { secureImageRepository.isDecoyPhoto($0) }.count
    }
    
    func selectedPhotos() async -> [UIImage] {
        let selected = photos.filter { selectedPhotoIds.contains($0) }
        var result: [UIImage] = []
        for photoDef in selected {
            do {
                let img = try await secureImageRepository.readImage(photoDef)
                result.append(img)
            } catch {
                Logger.storage.error("Error loading image", metadata: [
                    "photoName": .string(photoDef.photoName),
                    "error": .string(String(describing: error))
                ])
            }
        }
        return result
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
    
    func onSelectedPhotoChange(_ newValue: PhotoDef?) {
        if newValue == nil {
            loadPhotos()
        }
    }
    
    func handlePhotoTap(_ photo: PhotoDef) {
        if isSelecting {
            togglePhotoSelection(photo)
        } else {
            selectedPhoto = photo
        }
    }
    
    func togglePhotoSelection(_ photo: PhotoDef) {
        if selectedPhotoIds.contains(photo) {
            selectedPhotoIds.remove(photo)
        } else {
            // If we're selecting decoys and already at the limit, don't allow more selections
            if isSelectingDecoys && selectedPhotoIds.count >= maxDecoys {
                showDecoyLimitWarning = true
                return
            }
            selectedPhotoIds.insert(photo)
        }
    }
    
    func prepareToDeleteSinglePhoto(_ photo: PhotoDef) {
        selectedPhotoIds = [photo]
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

                Logger.ui.info("Importing photos", metadata: [
                    "count": .stringConvertible(importCount)
                ])

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
        Logger.ui.debug("deleteSelectedPhotos() called")
        
        // Create a local copy of the photos to delete
        let photosToDelete = selectedPhotoIds.compactMap { photo in
            photos.first(where: { $0 == photo })
        }
        
        Logger.ui.info("Will delete photos", metadata: [
            "count": .stringConvertible(photosToDelete.count),
            "photoNames": .string(photosToDelete.map { $0.photoName }.joined(separator: ", "))
        ])

        // Clear selection and exit selection mode immediately
        // for better UI responsiveness
        selectedPhotoIds.removeAll()
        isSelecting = false

        // Process deletions in a background queue
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            Logger.ui.debug("Starting background deletion process")

            // Delete each photo
            for photoDef in photosToDelete {
                Logger.ui.debug("Attempting to delete photo", metadata: [
                    "photoName": .string(photoDef.photoName)
                ])
                await self.secureImageRepository.deleteImage(photoDef)
                Logger.ui.debug("Successfully deleted photo", metadata: [
                    "photoName": .string(photoDef.photoName)
                ])
            }

            // After all deletions are complete, update the UI
            await MainActor.run {
                Logger.ui.debug("All deletions complete, updating UI")
                
                // Count photos before removal
                let initialCount = self.photos.count
                
                // Remove deleted photos from our array
                withAnimation {
                    self.photos.removeAll { photoDef in
                        let shouldRemove = photosToDelete.contains { $0.photoName == photoDef.photoName }
                        if shouldRemove {
                            Logger.ui.debug("Removing photo from UI", metadata: [
                                "photoName": .string(photoDef.photoName)
                            ])
                        }
                        return shouldRemove
                    }
                }
                
                // Verify removal
                let finalCount = self.photos.count
                let removedCount = initialCount - finalCount
                Logger.ui.info("UI update complete", metadata: [
                    "removedCount": .stringConvertible(removedCount),
                    "finalCount": .stringConvertible(finalCount)
                ])
            }
        }
    }
    
    func saveDecoySelections() {
        Task {
            // First, un-mark any previously tagged decoys that aren't currently selected
            for photoDef in photos {
                let isCurrentlySelected = selectedPhotoIds.contains(photoDef)
                let isCurrentlyDecoy = secureImageRepository.isDecoyPhoto(photoDef)
                
                // If it's currently a decoy but not selected, unmark it
                if isCurrentlyDecoy && !isCurrentlySelected {
                    secureImageRepository.removeDecoyPhoto(photoDef)
                }
                // If it's selected but not a decoy, mark it
                else if isCurrentlySelected && !isCurrentlyDecoy {
                    let success = await addDecoyPhotoUseCase.addDecoyPhoto(photoDef: photoDef)
                    if !success {
                        Logger.ui.error("Failed to add decoy photo \(photoDef)")
                    } else {
                        Logger.ui.error("Set photo as decoy \(photoDef)")
                    }
                }
            }
            
            // Reset selection and exit decoy mode
            isSelectingDecoys = false
            isSelecting = false
            selectedPhotoIds.removeAll()
        }
    }
    
    func shareSelectedPhotos() {
        Task {
            // Get all the selected photos
            let images = await selectedPhotos()
            guard !images.isEmpty else { return }
            
            // Find the root view controller
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let rootViewController = window.rootViewController
            else {
                Logger.ui.error("Could not find root view controller")
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
                        let fileURL = try prepareForSharingUseCase.preparePhotoForSharing(imageData: imageData)
                        filesToShare.append(fileURL)
                        Logger.ui.debug("Prepared file for sharing", metadata: [
                            "filename": .string(fileURL.lastPathComponent)
                        ])
                    } catch {
                        Logger.ui.error("Error preparing photo for sharing", metadata: [
                            "error": .string(error.localizedDescription)
                        ])
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
                    Logger.ui.info("Share sheet presented successfully", metadata: [
                        "fileCount": .stringConvertible(filesToShare.count)
                    ])
                }
            } else {
                // Fallback to sharing just the images if file preparation failed for all
                Logger.ui.debug("Falling back to sharing images directly")
                
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
    }
    
    func clearMemoryForPhoto(_ photoDef: PhotoDef) {
        self.secureImageRepository.thumbnailCache.evictThumbnail(photoDef)
    }
    
    func clearMemoryForAllPhotos() {
        // Clean up memory for all loaded images
        self.secureImageRepository.thumbnailCache.clear()
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
            
            // Load photo metadata
            let photoMetadata = await self.secureImageRepository.getPhotos()

            // Sort photos by creation date (newest first, which is more typical for photo galleries)
            let sortedPhotos = photoMetadata.sorted { photoDef1, photoDef2 in
                let date1 = photoDef1.dateTaken() ?? Date.distantPast
                let date2 = photoDef2.dateTaken() ?? Date.distantPast
                return date1 > date2 // Newest first
            }

            // Update UI on the main thread
            await MainActor.run {
                // First clear memory of existing photos if we're refreshing
                self.secureImageRepository.thumbnailCache.clear()

                // Update the photos array
                self.photos = sortedPhotos

                // If in decoy selection mode, pre-select existing decoy photos
                if self.isSelectingDecoys {
                    // Find and select all photos that are already marked as decoys
                    for photoDef in sortedPhotos {
                        if self.secureImageRepository.isDecoyPhoto(photoDef) {
                            self.selectedPhotoIds.insert(photoDef)
                        }
                    }

                    // Enable selection mode
                    self.isSelecting = true
                }
            }
        }
    }
    
    private func processImportedImageData(_ imageData: Data) async {
        // Save the photo data (runs on background thread)
        let filename = await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    let image = UIImage(data: imageData)!
                    let capturedImage = await CapturedImage(
                        sensorBitmap: image, timestamp: self.clock.now, rotationDegrees: 0
                    )
                    // TODO: We should extract some info out of the existing meta data
                    let newDef = try await self.secureImageRepository.saveImage(
                        capturedImage,
                        location: nil,
                        applyRotation: true
                    )
                    continuation.resume(returning: newDef.photoName)
                } catch {
                    Logger.storage.error("Error saving imported photo", metadata: [
                        "error": .string(error.localizedDescription)
                    ])
                    continuation.resume(returning: "")
                }
            }
        }

        if !filename.isEmpty {
            Logger.storage.info("Successfully imported photo", metadata: [
                "filename": .string(filename)
            ])
        }
    }
    
    // Legacy method for backward compatibility
    private func handleImportedImage() {
        guard let image = importedImage else { return }

        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            Logger.storage.error("Failed to convert image to data")
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
    
    private func deletePhoto(_ photoDef: PhotoDef) {
        // Perform file deletion in background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            
            await self.secureImageRepository.deleteImage(photoDef)

            // Update UI on main thread
            await MainActor.run {
                // Remove from the local array
                withAnimation {
                    self.photos.removeAll { $0 == photoDef }
                    if self.selectedPhotoIds.contains(photoDef) {
                        self.selectedPhotoIds.remove(photoDef)
                    }
                }
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

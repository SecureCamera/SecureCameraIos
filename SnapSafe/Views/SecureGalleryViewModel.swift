//
//  SecureGalleryViewModel.swift
//  SnapSafe
//
//  Created by Bill Booth on 6/27/25.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
class SecureGalleryViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var photos: [SecurePhoto] = []
    @Published var isSelecting: Bool = false
    @Published var selectedPhotoIds = Set<String>()
    @Published var isImporting: Bool = false
    @Published var importProgress: Float = 0
    @Published var showDeleteConfirmation = false
    @Published var showDecoyLimitWarning: Bool = false
    @Published var showDecoyConfirmation: Bool = false

    // MARK: - Private Properties

    private let secureFileManager = SecureFileManager()
    private let maxDecoys: Int = 10

    // MARK: - Computed Properties

    var hasSelection: Bool {
        !selectedPhotoIds.isEmpty
    }

    var selectedPhotos: [UIImage] {
        photos
            .filter { selectedPhotoIds.contains($0.id) }
            .map(\.fullImage)
    }

    // MARK: - Photo Loading

    func loadPhotos() {
        // Load photos in the background thread to avoid UI blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

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
                    self.photos = loadedPhotos

                    // Register these photos with the memory manager
                    MemoryManager.shared.registerPhotos(loadedPhotos)
                }
            } catch {
                print("Error loading photos: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Selection Management

    func togglePhotoSelection(_ photo: SecurePhoto, isSelectingDecoys: Bool) {
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

    func startSelection() {
        isSelecting = true
    }

    func cancelSelection() {
        isSelecting = false
        selectedPhotoIds.removeAll()
    }

    func prepareToDeleteSinglePhoto(_ photo: SecurePhoto) {
        selectedPhotoIds = [photo.id]
        showDeleteConfirmation = true
    }

    func enableDecoySelection() {
        // Find and select all photos that are already marked as decoys
        for photo in photos {
            if photo.isDecoy {
                selectedPhotoIds.insert(photo.id)
            }
        }

        // Enable selection mode
        isSelecting = true
    }

    // MARK: - Import Operations

    func processPhotoImport(from pickerItems: [PhotosPickerItem]) {
        Task {
            var hadSuccessfulImport = false

            // Show import progress to user
            let importCount = pickerItems.count
            if importCount > 0 {
                // Update UI to show import is happening
                await MainActor.run {
                    isImporting = true
                    importProgress = 0
                }

                print("Importing \(importCount) photos...")

                // Process each selected item with progress tracking
                for (index, item) in pickerItems.enumerated() {
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

            // After importing all items, reset the import state and refresh gallery
            await MainActor.run {
                // Hide progress indicator
                isImporting = false

                // Reload the gallery if we imported images
                if hadSuccessfulImport {
                    loadPhotos()
                }
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
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    continuation.resume(returning: "")
                    return
                }

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

    // MARK: - Deletion Operations

    func deleteSelectedPhotos() {
        print("deleteSelectedPhotos() called")

        // Create a local copy of the photos to delete
        let photosToDelete = selectedPhotoIds.compactMap { id in
            photos.first(where: { $0.id == id })
        }

        print("Will delete \(photosToDelete.count) photos: \(photosToDelete.map(\.id).joined(separator: ", "))")

        // Clear selection and exit selection mode immediately
        // for better UI responsiveness
        DispatchQueue.main.async { [weak self] in
            print("Clearing selection UI state")
            self?.selectedPhotoIds.removeAll()
            self?.isSelecting = false
        }

        // Process deletions in a background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

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
            group.notify(queue: .main) { [weak self] in
                guard let self else { return }

                print("All deletions complete, updating UI")

                // Count photos before removal
                let initialCount = photos.count

                // Remove deleted photos from our array
                withAnimation {
                    self.photos.removeAll { photo in
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

    // MARK: - Sharing Operations

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

    // MARK: - Decoy Management

    func validateDecoySelection() -> Bool {
        selectedPhotoIds.count <= maxDecoys
    }

    func saveDecoySelections() {
        // TODO: Implement decoy status update with new repository pattern
        // This will be implemented when we extend SecurePhotoRepository

        // For now, just reset selection state
        selectedPhotoIds.removeAll()
    }

    // MARK: - Cleanup

    func cleanupMemory() {
        // Clean up memory for all loaded full-size images when returning to gallery
        for photo in photos {
            photo.clearMemory(keepThumbnail: true)
        }
        // Trigger garbage collection
        MemoryManager.shared.checkMemoryUsage()
    }
}

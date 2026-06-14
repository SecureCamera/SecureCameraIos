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
import Logging


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
    
    // Zoom and pan states
    @Published var currentScale: CGFloat = 1.0

    @Published var showImageInfo = false
    @Published var isPoisonPillConfigured = false
    
    // Track currently presented activity controller for dismissal
    // MARK: - Dependencies
    
    @Injected(\.pinRepository)
    private var pinRepository: PinRepository
    
    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(photo: PhotoDef, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.singlePhotoFile = photo
        self.onDelete = onDelete
        self.onDismiss = onDismiss
        setupSecurityObservers()
        
        // Load the image immediately
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
        return currentImage ?? UIImage(systemName: "photo")!
    }
    
    func isPoisonPillSetup() async -> Bool {
        return await pinRepository.hasPoisonPillPin()
    }

    // MARK: - Image Loading
    
    private func loadCurrentImage() async {
        guard let photoDef = currentPhotoDef else { return }
        
        isImageLoading = true
        
        do {
            let data = try await secureImageRepository.readImage(photoDef)
            guard let image = UIImage(data: data) else { throw ImageRepositoryError.invalidImageData }
            await MainActor.run {
                self.currentImage = image
                self.isImageLoading = false
            }
        } catch {
            Logger.storage.error("Error loading image", metadata: [
                "error": .string(String(describing: error))
            ])
            await MainActor.run {
                self.currentImage = UIImage(systemName: "photo")
                self.isImageLoading = false
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
                _ = await secureImageRepository.readThumbnail(prevPhotoDef)
            }
        }
        
        // Preload next photo if available
        if currentIndex < photoFiles.count - 1 {
            let nextIndex = currentIndex + 1
            let nextPhotoDef = photoFiles[nextIndex]
            
            // Preload thumbnail in background
            Task(priority: .userInitiated) {
                _ = await secureImageRepository.readThumbnail(nextPhotoDef)
            }
        }
    }

    // MARK: - Photo Management

    func deleteCurrentPhoto() {
        Logger.ui.debug("deleteCurrentPhoto called - starting deletion process")
        
        guard let photoDefToDelete = currentPhotoDef else { return }
        
        // Perform file deletion in a background thread
        Task(priority: .userInitiated) {
            // Actually delete the file
            Logger.ui.debug("Attempting to delete file", metadata: [
                "filename": .string(photoDefToDelete.photoName)
            ])
            _ = await self.secureImageRepository.deleteImage(photoDefToDelete)
            Logger.ui.debug("File deletion successful")
            
            // All UI updates must happen on the main thread
            await MainActor.run {
                Logger.ui.debug("Calling onDelete callback")
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
    
    // MARK: - View Lifecycle
    
    func onAppear() {
        // Check poison pill status
        Task {
            let hasPoisonPill = await isPoisonPillSetup()
            await MainActor.run {
                self.isPoisonPillConfigured = hasPoisonPill
            }
        }
        
        // Preload adjacent photos for smoother navigation
        Task {
            try await Task.sleep(for: .milliseconds(200))
            await MainActor.run {
                self.preloadAdjacentPhotos()
            }
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
        showDeleteConfirmation = false
        showImageInfo = false
        
    }
}

//
//  EnhancedPhotoDetailViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/9/25.
//

import SwiftUI
import FactoryKit
import Logging

@MainActor
class EnhancedPhotoDetailViewModel: ObservableObject {
    // MARK: - Dependencies

    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository

    @Injected(\.prepareForSharingUseCase)
    private var prepareForSharingUseCase: PrepareForSharingUseCase

    @Injected(\.addDecoyPhotoUseCase)
    private var addDecoyPhotoUseCase: AddDecoyPhotoUseCase

    @Injected(\.removeDecoyPhotoUseCase)
    private var removeDecoyPhotoUseCase: RemoveDecoyPhotoUseCase

    @Injected(\.pinRepository)
    private var pinRepository: PinRepository
    
    // MARK: - Published Properties
    
    @Published var photoFiles: [PhotoDef] = []
    @Published var currentIndex: Int = 0
    @Published var dragOffset: CGSize = .zero
    @Published var dismissProgress: CGFloat = 0
    @Published var isTabViewTransitioning: Bool = false
    @Published var lastIndexChangeTime: Date = Date()

    // Toolbar state
    @Published var showImageInfo = false
    @Published var showDeleteConfirmation = false
    @Published var isDecoyOperationLoading = false
    @Published var isPoisonPillConfigured = false

    // Track currently presented activity controller for dismissal
    private weak var currentActivityController: UIActivityViewController?
    
    // MARK: - Configuration
    
    var onDelete: ((PhotoDef) -> Void)?
    var onDismiss: (() -> Void)?
    
    // MARK: - Initialization
    
    init(allPhotos: [PhotoDef], initialIndex: Int, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.photoFiles = allPhotos
        self.currentIndex = initialIndex
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }
    
    // MARK: - Computed Properties
    
    var photoCount: Int {
        photoFiles.count
    }
    
    var currentPhotoDisplayText: String {
        "\(currentIndex + 1) of \(photoCount)"
    }
    
    var backgroundOpacity: Double {
        1.0 - dismissProgress * 0.8
    }
    
    var photoScaleEffect: Double {
        1.0 - dismissProgress * 0.2
    }
    
    var overlayOpacity: Double {
        1.0 - dismissProgress
    }

    // Current photo computed properties
    var currentPhotoDef: PhotoDef? {
        guard currentIndex < photoFiles.count else { return nil }
        return photoFiles[currentIndex]
    }


    var isCurrentPhotoDecoy: Bool {
        guard let photoDef = currentPhotoDef else { return false }
        return secureImageRepository.isDecoyPhoto(photoDef)
    }

    var decoyButtonTitle: String {
        isCurrentPhotoDecoy ? "Remove Decoy" : "Add Decoy"
    }

    var decoyButtonIcon: String {
        isCurrentPhotoDecoy ? "shield.slash" : "shield"
    }
    
    // MARK: - Index Management
    
    func handleIndexChange(newIndex: Int) {
        Logger.ui.debug("EnhancedPhotoDetailViewModel: currentIndex changed", metadata: [
            "from": .stringConvertible(currentIndex),
            "to": .stringConvertible(newIndex)
        ])
        
        // Track when TabView transitions occur
        isTabViewTransitioning = true
        lastIndexChangeTime = Date()
        
        // Reset any dismiss progress during navigation
        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = .zero
            dismissProgress = 0
        }
        
        // Preload adjacent photos when index changes
        preloadAdjacentPhotos(currentIndex: newIndex)
        
        // Clear transition state after a delay
        Task {
            try await Task.sleep(for: .milliseconds(800))
            await MainActor.run {
                self.isTabViewTransitioning = false
            }
        }
    }
    
    // MARK: - Preloading
    
    func preloadAdjacentPhotos(currentIndex: Int) {
        guard !photoFiles.isEmpty else { return }
        
        // Preload previous photo thumbnail
        if currentIndex > 0 {
            let previousPhotoDef = photoFiles[currentIndex - 1]
            Task(priority: .userInitiated) {
                _ = await secureImageRepository.readThumbnail(previousPhotoDef)
            }
        }
        
        // Preload next photo thumbnail
        if currentIndex < photoFiles.count - 1 {
            let nextPhotoDef = photoFiles[currentIndex + 1]
            Task(priority: .userInitiated) {
                _ = await secureImageRepository.readThumbnail(nextPhotoDef)
            }
        }
    }
    
    // MARK: - Gesture Handling
    
    func handleDragChanged(_ value: DragGesture.Value, geometryHeight: CGFloat) {
        // Bail out until the drag is clearly vertical
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        
        dragOffset = CGSize(width: 0, height: value.translation.height)
        dismissProgress = min(value.translation.height / (geometryHeight * 0.4), 1.0)
    }
    
    func handleDragEnded(_ value: DragGesture.Value, geometryHeight: CGFloat, dismiss: @escaping () -> Void) {
        // Same dominant-axis guard here *before* any threshold checks
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        
        let dismissThreshold = geometryHeight * 0.25
        let isQuickDownSwipe = value.velocity.height > 2000
        
        if value.translation.height > dismissThreshold || isQuickDownSwipe {
            // Dismiss the view
            withAnimation(.easeOut(duration: 0.3)) {
                dragOffset = CGSize(width: 0, height: geometryHeight)
                dismissProgress = 1
            }
            
            Task {
                try await Task.sleep(for: .milliseconds(100))
                await MainActor.run {
                    self.onDismiss?()
                    dismiss()
                }
            }
        } else {
            // Return to original position
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                dragOffset = .zero
                dismissProgress = 0
            }
        }
    }
    
    // MARK: - View Lifecycle
    
    func onAppear() {
        preloadAdjacentPhotos(currentIndex: currentIndex)
        loadPoisonPillConfiguration()
    }

    func loadPoisonPillConfiguration() {
        Task {
            let hasPoisonPill = await pinRepository.hasPoisonPillPin()
            await MainActor.run {
                isPoisonPillConfigured = hasPoisonPill
            }
        }
    }
    
    // MARK: - Photo Management
    
    func deletePhoto(at index: Int) {
        guard index < photoFiles.count else { return }

        let photoDefToDelete = photoFiles[index]

        // Perform file deletion in a background thread
        Task(priority: .userInitiated) {
            // Actually delete the file
            Logger.ui.debug("Attempting to delete file", metadata: [
                "filename": .string(photoDefToDelete.photoName)
            ])
            secureImageRepository.deleteImage(photoDefToDelete)
            Logger.ui.debug("File deletion successful")

            // All UI updates must happen on the main thread
            await MainActor.run {
                Logger.ui.debug("Calling onDelete callback")
                onDelete?(photoDefToDelete)
            }
        }
    }

    // MARK: - Toolbar Actions

    func shareCurrentPhoto() {
        guard let photoDef = currentPhotoDef else { return }

        Task {
            do {
                // First load the image
                let image = try await secureImageRepository.readImage(photoDef)

                // Convert image to data for sharing with UUID filename
                if let imageData = image.jpegData(compressionQuality: 0.9) {
                    // Prepare photo for sharing with UUID filename
                    let fileURL = try prepareForSharingUseCase.preparePhotoForSharing(imageData: imageData)

                    Logger.ui.debug("Photo prepared for sharing successfully")

                    // Create activity controller with the temporary image
                    let activityController = UIActivityViewController(
                        activityItems: [fileURL],
                        applicationActivities: nil
                    )

                    // Store reference for potential dismissal
                    currentActivityController = activityController

                    // Present the activity controller
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {

                        var presentingViewController = rootViewController
                        while let presentedViewController = presentingViewController.presentedViewController {
                            presentingViewController = presentedViewController
                        }

                        await MainActor.run {
                            presentingViewController.present(activityController, animated: true)
                        }
                    }
                }
            } catch {
                Logger.ui.error("Failed to prepare photo for sharing", metadata: ["error": .string(error.localizedDescription)])
            }
        }
    }

    func toggleDecoyStatus() {
        guard let photoDef = currentPhotoDef else { return }

        isDecoyOperationLoading = true

        Task {
            if isCurrentPhotoDecoy {
                Logger.ui.debug("Removing decoy status from photo", metadata: ["photoId": .stringConvertible(photoDef.id)])
                await MainActor.run {
                    _ = removeDecoyPhotoUseCase.removeDecoyPhoto(photoDef)
                    isDecoyOperationLoading = false
                }
            } else {
                Logger.ui.debug("Adding decoy status to photo", metadata: ["photoId": .stringConvertible(photoDef.id)])
                // Add decoy status
                let success = await addDecoyPhotoUseCase.addDecoyPhoto(photoDef: photoDef)
                await MainActor.run {
                    isDecoyOperationLoading = false
                }

                if success {
                    Logger.ui.info("Successfully added decoy status")
                } else {
                    Logger.ui.error("Failed to add decoy status")
                }
            }
        }
    }
}

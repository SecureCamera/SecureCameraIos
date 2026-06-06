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

    @Published var allMedia: [GalleryMediaItem] = []
    @Published var currentIndex: Int = 0
    @Published var dragOffset: CGSize = .zero
    @Published var dismissProgress: CGFloat = 0
    @Published var isTabViewTransitioning: Bool = false
    @Published var lastIndexChangeTime: Date = Date()
    /// Tracks whether the inline video player on the current page is showing
    /// its glass controls. Photos always treat this as visible.
    @Published var isVideoControlsVisible: Bool = true

    /// Whether the "X of Y" counter chip is currently shown. It auto-hides a
    /// few seconds after appearing / after each page change so it stops
    /// covering the image.
    @Published var isCounterVisible: Bool = true
    private var counterHideTask: Task<Void, Never>?

    /// How long the counter stays visible before fading out.
    private let counterVisibleDuration: Duration = .seconds(5)

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

    init(allMedia: [GalleryMediaItem], initialIndex: Int, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.allMedia = allMedia
        self.currentIndex = initialIndex
        self.onDelete = onDelete
        self.onDismiss = onDismiss
    }

    @Published internal var isZoomed: Bool = false

    // Policy helpers (clear/consistent call sites + unit-testable)
    @inlinable internal func mayDismissByDrag() -> Bool { !isZoomed }
    @inlinable internal func mayPageHorizontally() -> Bool { !isZoomed }

    // MARK: - Computed Properties

    var mediaCount: Int { allMedia.count }

    /// Convenience: photo-only slice preserved for preloading thumbnails.
    var photoFiles: [PhotoDef] { allMedia.compactMap { $0.photoDef } }

    var currentPhotoDisplayText: String {
        "\(currentIndex + 1) of \(mediaCount)"
    }

    var backgroundOpacity: Double {
        1.0 - dismissProgress * 0.8
    }

    var photoScaleEffect: Double {
        1.0 - dismissProgress * 0.2
    }

    var overlayOpacity: Double {
        if isZoomed { return 0.0 }
        if !isCounterVisible { return 0.0 }
        if currentIsVideo && !isVideoControlsVisible { return 0.0 }
        return 1.0 - dismissProgress
    }

    /// The current item regardless of type.
    var currentMediaItem: GalleryMediaItem? {
        guard currentIndex < allMedia.count else { return nil }
        return allMedia[currentIndex]
    }

    /// Non-nil only when the current page is a photo.
    var currentPhotoDef: PhotoDef? {
        currentMediaItem?.photoDef
    }

    /// True when the current page is a video.
    var currentIsVideo: Bool {
        currentMediaItem?.mediaType == .video
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

        isTabViewTransitioning = true
        lastIndexChangeTime = Date()

        withAnimation(.easeOut(duration: 0.2)) {
            dragOffset = .zero
            dismissProgress = 0
        }

        // Re-show the counter for the newly visible item, then fade it again.
        showCounterThenAutoHide()

        preloadAdjacentPhotos(currentIndex: newIndex)

        Task {
            try await Task.sleep(for: .milliseconds(800))
            await MainActor.run {
                self.isTabViewTransitioning = false
            }
        }
    }

    // MARK: - Preloading

    func preloadAdjacentPhotos(currentIndex: Int) {
        // Preload only photo thumbnails (video thumbnails are loaded by their cells)
        if currentIndex > 0, let prev = allMedia[currentIndex - 1].photoDef {
            Task(priority: .userInitiated) {
                _ = await secureImageRepository.readThumbnail(prev)
            }
        }
        if currentIndex < allMedia.count - 1, let next = allMedia[currentIndex + 1].photoDef {
            Task(priority: .userInitiated) {
                _ = await secureImageRepository.readThumbnail(next)
            }
        }
    }

    // MARK: - Gesture Handling

    func handleDragChanged(_ value: DragGesture.Value, geometryHeight: CGFloat) {
        guard abs(value.translation.height) > abs(value.translation.width) else { return }
        dragOffset = CGSize(width: 0, height: value.translation.height)
        dismissProgress = min(value.translation.height / (geometryHeight * 0.4), 1.0)
    }

    func handleDragEnded(_ value: DragGesture.Value, geometryHeight: CGFloat, dismiss: @escaping () -> Void) {
        guard abs(value.translation.height) > abs(value.translation.width) else { return }

        let dismissThreshold = geometryHeight * 0.25
        let isQuickDownSwipe = value.velocity.height > 2000

        if value.translation.height > dismissThreshold || isQuickDownSwipe {
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
        showCounterThenAutoHide()
    }

    /// Shows the counter chip and (for photos) schedules it to fade out after
    /// `counterVisibleDuration`. Cancels any previously scheduled hide so the
    /// timer restarts cleanly on each page change or tap.
    ///
    /// On video pages we don't run the timer: the counter there follows the
    /// inline player's own control visibility (`isVideoControlsVisible`), which
    /// already auto-hides.
    func showCounterThenAutoHide() {
        counterHideTask?.cancel()
        if !isCounterVisible {
            withAnimation(.easeInOut(duration: 0.25)) { isCounterVisible = true }
        }

        guard !currentIsVideo else { return }

        counterHideTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.counterVisibleDuration)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.5)) { self.isCounterVisible = false }
        }
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
        guard index < allMedia.count,
              let photoDef = allMedia[index].photoDef else { return }

        Task(priority: .userInitiated) {
            Logger.ui.debug("Attempting to delete file", metadata: [
                "filename": .string(photoDef.photoName)
            ])
            secureImageRepository.deleteImage(photoDef)
            Logger.ui.debug("File deletion successful")
            await MainActor.run {
                Logger.ui.debug("Calling onDelete callback")
                onDelete?(photoDef)
            }
        }
    }

    // MARK: - Toolbar Actions

    func shareCurrentPhoto() {
        guard let photoDef = currentPhotoDef else { return }

        Task {
            do {
                let image = try await secureImageRepository.readImage(photoDef)

                if let imageData = image.jpegData(compressionQuality: 0.9) {
                    let fileURL = try prepareForSharingUseCase.preparePhotoForSharing(imageData: imageData)

                    Logger.ui.debug("Photo prepared for sharing successfully")

                    let activityController = UIActivityViewController(
                        activityItems: [fileURL],
                        applicationActivities: nil
                    )

                    currentActivityController = activityController

                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {

                        var presentingViewController = rootViewController
                        while let presentedViewController = presentingViewController.presentedViewController {
                            presentingViewController = presentedViewController
                        }

                        await MainActor.run {
                            if let popoverController = activityController.popoverPresentationController {
                                popoverController.sourceView = presentingViewController.view
                                popoverController.sourceRect = CGRect(
                                    x: presentingViewController.view.bounds.midX,
                                    y: presentingViewController.view.bounds.midY,
                                    width: 0,
                                    height: 0
                                )
                                popoverController.permittedArrowDirections = []
                            }
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

//
//  MixedMediaGalleryViewModel.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import Foundation
import PhotosUI
import SwiftUI
import Combine
import FactoryKit
import Logging
import CryptoKit
import CoreTransferable
import UniformTypeIdentifiers

/// A movie loaded from the photo library, copied to a temporary location we own.
struct ImportedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: received.file, to: temp)
            return ImportedMovie(url: temp)
        }
    }
}

/// Gallery selection modes.
enum SelectionMode {
    case none
    case share
    case delete
    case decoy
}

/// Enhanced gallery view model that supports both photos and videos.
@MainActor
final class MixedMediaGalleryViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var mediaItems: [GalleryMediaItem] = []
    @Published var selectedMediaItem: GalleryMediaItem?
    @Published var selectionMode: SelectionMode = .none
    @Published var selectedMediaIds = Set<UUID>()
    @Published var showDeleteConfirmation = false
    @Published var isShowingImagePicker = false
    @Published var importedImage: UIImage?
    @Published var pickerItems: [PhotosPickerItem] = []
    @Published var isImporting: Bool = false
    @Published var importProgress: Float = 0
    @Published var showVideoPlayer = false
    @Published var currentVideoItem: GalleryMediaItem?

    // Decoy support
    var isSelecting: Bool { selectionMode != .none }
    var isSelectingDecoys: Bool { selectionMode == .decoy }
    @Published var maxDecoys: Int = 10
    @Published var showDecoyLimitWarning: Bool = false
    @Published var showDecoyConfirmation: Bool = false
    @Published var isPoisonPillConfigured: Bool = false

    /// Set while `saveDecoySelections()` is running. Decoy videos are re-encrypted
    /// with the poison-pill key, which can take a while for large videos.
    @Published var isSavingDecoys: Bool = false
    @Published var decoySaveTotal: Int = 0
    @Published var decoySaveCompleted: Int = 0

    // MARK: - Dependencies

    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository

    @Injected(\.videoEncryptionService)
    private var videoEncryptionService: VideoEncryptionService

    @Injected(\.clock)
    private var clock: Clock

    @Injected(\.addDecoyPhotoUseCase)
    private var addDecoyPhotoUseCase: AddDecoyPhotoUseCase

    @Injected(\.removeDecoyPhotoUseCase)
    private var removeDecoyPhotoUseCase: RemoveDecoyPhotoUseCase

    @Injected(\.addDecoyVideoUseCase)
    private var addDecoyVideoUseCase: AddDecoyVideoUseCase

    @Injected(\.prepareForSharingUseCase)
    private var prepareForSharingUseCase: PrepareForSharingUseCase

    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository

    @Injected(\.pinRepository)
    private var pinRepository: PinRepository

    @Injected(\.encryptionScheme)
    private var encryptionScheme: EncryptionScheme

    private var cancellables = Set<AnyCancellable>()
    private weak var currentActivityController: UIActivityViewController?
    private var encryptionKey: SymmetricKey?

    // MARK: - Initialization

    init(selectingDecoys: Bool = false) {
        self.selectionMode = selectingDecoys ? .decoy : .none

        setupObservers()
    }

    // MARK: - View Lifecycle

    func onAppear() {
        Task {
            // Load encryption key first so videos get the key attached
            do {
                let keyData = try await encryptionScheme.getDerivedKey()
                encryptionKey = SymmetricKey(data: keyData)
            } catch {
                Logger.storage.error("Failed to get encryption key for gallery", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
            // Now load media items (uses encryptionKey for video items)
            loadMediaItems()
        }
        loadPoisonPillConfiguration()
    }

    private func loadPoisonPillConfiguration() {
        Task {
            let hasPoisonPill = await pinRepository.hasPoisonPillPin()
            await MainActor.run {
                isPoisonPillConfigured = hasPoisonPill
            }
        }
    }

    // MARK: - Computed Properties

    var hasSelection: Bool {
        !selectedMediaIds.isEmpty
    }

    /// All photos from the media items (convenience for photo-specific operations).
    var photos: [PhotoDef] {
        mediaItems.compactMap { $0.photoDef }
    }

    var currentDecoyCount: Int {
        let photoDecoys = mediaItems.compactMap { $0.photoDef }.filter { secureImageRepository.isDecoyPhoto($0) }.count
        let videoDecoys = mediaItems.compactMap { $0.videoDef }.filter { secureImageRepository.isDecoyVideo($0) }.count
        return photoDecoys + videoDecoys
    }

    /// Whether the given media item is currently marked as a decoy.
    private func isItemDecoy(_ item: GalleryMediaItem) -> Bool {
        if let photoDef = item.photoDef {
            return secureImageRepository.isDecoyPhoto(photoDef)
        } else if let videoDef = item.videoDef {
            return secureImageRepository.isDecoyVideo(videoDef)
        }
        return false
    }

    var navigationTitle: String {
        if isSelectingDecoys {
            return "Select Decoy Media"
        } else {
            return "Secure Gallery"
        }
    }

    var decoyCountText: String {
        "\(selectedMediaIds.count)/\(maxDecoys)"
    }

    var decoyCountTextColor: Color {
        selectedMediaIds.count > maxDecoys ? .red : .secondary
    }

    var isSaveDecoyButtonDisabled: Bool {
        selectedMediaIds.isEmpty || isSavingDecoys
    }

    var deleteAlertTitle: String {
        "Delete \(selectedMediaIds.count > 1 ? "Items" : "Item")"
    }

    var deleteAlertMessage: String {
        "Are you sure you want to delete \(selectedMediaIds.count) item\(selectedMediaIds.count > 1 ? "s" : "")? This action cannot be undone."
    }

    var decoyConfirmationMessage: String {
        "Are you sure you want to save these \(selectedMediaIds.count) items as decoys? These will be shown when the emergency PIN is entered."
    }

    var decoyLimitWarningMessage: String {
        "You can select a maximum of \(maxDecoys) decoy items. Please deselect some before saving."
    }

    // MARK: - Media Loading

    func loadMediaItems() {
        Task {
            // Load photos
            let photoMetadata = secureImageRepository.getPhotos()
            let encKey = encryptionKey
            let photos = photoMetadata.map { GalleryMediaItem(mediaItem: $0, encryptionKey: nil) }

            // Load videos
            let videos = loadVideos(encryptionKey: encKey)

            // Combine and sort by date (newest first)
            let allMedia = (photos + videos).sorted { item1, item2 in
                let date1 = item1.dateTaken() ?? Date.distantPast
                let date2 = item2.dateTaken() ?? Date.distantPast
                return date1 > date2
            }

            mediaItems = allMedia

            if isSelectingDecoys {
                for item in allMedia where isItemDecoy(item) {
                    selectedMediaIds.insert(item.id)
                }
            }
        }
    }

    private func loadVideos(encryptionKey: SymmetricKey?) -> [GalleryMediaItem] {
        let videosDirectory = getVideosDirectory()

        guard FileManager.default.fileExists(atPath: videosDirectory.path) else {
            return []
        }

        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: videosDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )

            let videoFiles = fileURLs.filter { url in
                let ext = url.pathExtension.lowercased()
                return ext == "secv"
            }

            return videoFiles.compactMap { videoURL in
                let fileName = videoURL.deletingPathExtension().lastPathComponent

                return GalleryMediaItem(
                    mediaItem: VideoDef(
                        videoName: fileName,
                        videoFormat: videoURL.pathExtension,
                        videoFile: videoURL
                    ),
                    encryptionKey: encryptionKey
                )
            }

        } catch {
            Logger.storage.error("Failed to load videos", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return []
        }
    }

    private func getVideosDirectory() -> URL {
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupportPath.appendingPathComponent("videos")
    }

    // MARK: - Selection

    func toggleSelection(for mediaItem: GalleryMediaItem) {
        if selectedMediaIds.contains(mediaItem.id) {
            selectedMediaIds.remove(mediaItem.id)
        } else {
            if isSelectingDecoys && selectedMediaIds.count >= maxDecoys {
                showDecoyLimitWarning = true
                return
            }
            selectedMediaIds.insert(mediaItem.id)
        }
    }

    func isSelected(_ mediaItem: GalleryMediaItem) -> Bool {
        selectedMediaIds.contains(mediaItem.id)
    }

    func clearSelection() {
        selectedMediaIds.removeAll()
    }

    func startSelecting(mode: SelectionMode) {
        selectionMode = mode

        if mode == .decoy {
            selectedMediaIds.removeAll()
            for item in mediaItems where isItemDecoy(item) {
                selectedMediaIds.insert(item.id)
            }
        }
    }

    func cancelSelecting() {
        selectionMode = .none
        selectedMediaIds.removeAll()
    }

    func exitDecoyMode() {
        selectionMode = .none
        selectedMediaIds.removeAll()
    }

    // MARK: - Media Item Tap Handling

    func handleMediaTap(_ item: GalleryMediaItem) {
        if isSelecting {
            toggleSelection(for: item)
        } else if item.mediaType == .video {
            // Navigate to video player via selectedMediaItem
            selectedMediaItem = item
        } else {
            // Navigate to photo detail via selectedMediaItem
            selectedMediaItem = item
        }
    }

    func prepareToDeleteSingleMedia(_ item: GalleryMediaItem) {
        selectedMediaIds = [item.id]
        showDeleteConfirmation = true
    }

    // MARK: - Alert Triggers

    func showDeleteAlert() {
        showDeleteConfirmation = true
    }

    func showDecoyConfirmationAlert() {
        if selectedMediaIds.count > maxDecoys {
            showDecoyLimitWarning = true
        } else {
            showDecoyConfirmation = true
        }
    }

    // MARK: - Media Operations

    func deleteSelectedMedia() {
        guard !selectedMediaIds.isEmpty else { return }

        let selectedItems = mediaItems.filter { selectedMediaIds.contains($0.id) }

        selectedMediaIds.removeAll()
        selectionMode = .none

        Task {
            for mediaItem in selectedItems {
                if let photoDef = mediaItem.photoDef {
                    secureImageRepository.deleteImage(photoDef)
                } else if let videoDef = mediaItem.videoDef {
                    try? FileManager.default.removeItem(at: videoDef.videoFile)
                    secureImageRepository.deleteVideoThumbnail(forVideoNamed: videoDef.videoName)
                    _ = secureImageRepository.removeDecoyVideo(videoDef)
                }
            }

            withAnimation {
                mediaItems.removeAll { item in
                    selectedItems.contains(where: { $0.id == item.id })
                }
            }
        }
    }

    // MARK: - Import Operations

    func processPickerItems(_ newItems: [PhotosPickerItem]) {
        guard !newItems.isEmpty else { return }

        isImporting = true
        importProgress = 0

        Task {
            var hadSuccessfulImport = false

            for (index, item) in newItems.enumerated() {
                importProgress = Float(index) / Float(newItems.count)

                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    if let movie = try? await item.loadTransferable(type: ImportedMovie.self) {
                        let imported = await secureImageRepository.importVideo(from: movie.url)
                        try? FileManager.default.removeItem(at: movie.url)
                        if imported { hadSuccessfulImport = true }
                    }
                } else if let data = try? await item.loadTransferable(type: Data.self) {
                    await processImportedImageData(data)
                    hadSuccessfulImport = true
                }
            }

            importProgress = 1.0
            try? await Task.sleep(nanoseconds: 300_000_000)

            pickerItems = []
            isImporting = false

            if hadSuccessfulImport {
                loadMediaItems()
            }
        }
    }

    private func processImportedImageData(_ imageData: Data) async {
        guard let image = UIImage(data: imageData) else { return }
        let capturedImage = CapturedImage(
            sensorBitmap: image, timestamp: clock.now, rotationDegrees: 0
        )
        do {
            _ = try await secureImageRepository.saveImage(
                capturedImage,
                location: nil,
                applyRotation: true
            )
        } catch {
            Logger.storage.error("Error saving imported photo", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }

    // MARK: - Decoy Operations

    func saveDecoySelections() async {
        // Only items whose decoy state actually changes need work.
        let pending = mediaItems.filter { selectedMediaIds.contains($0.id) != isItemDecoy($0) }

        guard !pending.isEmpty else {
            selectionMode = .none
            selectedMediaIds.removeAll()
            return
        }

        decoySaveTotal = pending.count
        decoySaveCompleted = 0
        isSavingDecoys = true
        // Give SwiftUI a beat to paint the overlay (and start the spinner
        // animation) before the synchronous re-encryption work begins.
        try? await Task.sleep(nanoseconds: 50_000_000)

        for item in pending {
            let isSelected = selectedMediaIds.contains(item.id)

            if let photoDef = item.photoDef {
                if isSelected {
                    if await addDecoyPhotoUseCase.addDecoyPhoto(photoDef: photoDef) == false {
                        Logger.ui.error("Failed to add decoy photo")
                    }
                } else {
                    _ = removeDecoyPhotoUseCase.removeDecoyPhoto(photoDef)
                }
            } else if let videoDef = item.videoDef {
                if isSelected {
                    if await addDecoyVideoUseCase.addDecoyVideo(videoDef: videoDef) == false {
                        Logger.ui.error("Failed to add decoy video")
                    }
                } else {
                    _ = secureImageRepository.removeDecoyVideo(videoDef)
                }
            }

            decoySaveCompleted += 1
            await Task.yield()
        }

        isSavingDecoys = false
        selectionMode = .none
        selectedMediaIds.removeAll()
    }

    // MARK: - Sharing Operations

    func shareSelectedMedia() {
        guard !selectedMediaIds.isEmpty else { return }

        Task {
            await prepareAndShareMedia()
        }
    }

    private func prepareAndShareMedia() async {
        let selectedItems = mediaItems.filter { selectedMediaIds.contains($0.id) }
        var itemsToShare: [Any] = []

        for mediaItem in selectedItems {
            if let photoDef = mediaItem.photoDef {
                if let image = try? await secureImageRepository.readImage(photoDef) {
                    if let imageData = image.jpegData(compressionQuality: 0.9) {
                        if let fileURL = try? prepareForSharingUseCase.preparePhotoForSharing(imageData: imageData) {
                            itemsToShare.append(fileURL)
                        }
                    }
                }
            } else if let videoDef = mediaItem.videoDef, videoDef.isEncrypted, let encryptionKey = encryptionKey {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("temp_\(videoDef.videoName).mov")

                FileManager.default.createFile(atPath: tempURL.path, contents: nil)

                do {
                    try await videoEncryptionService.decryptVideoForSharing(
                        inputURL: videoDef.videoFile,
                        outputURL: tempURL,
                        encryptionKey: encryptionKey
                    )
                    itemsToShare.append(tempURL)
                } catch {
                    Logger.media.error("Failed to decrypt video for sharing", metadata: [
                        "error": .string(error.localizedDescription)
                    ])
                }
            } else if let videoDef = mediaItem.videoDef {
                itemsToShare.append(videoDef.videoFile)
            }
        }

        await MainActor.run {
            presentShareSheet(with: itemsToShare)
        }
    }

    private func presentShareSheet(with items: [Any]) {
        guard !items.isEmpty else { return }

        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        currentActivityController = activityViewController

        activityViewController.completionWithItemsHandler = { [weak self] _, completed, _, error in
            if completed {
                Logger.media.info("Media shared successfully")
            } else if let error = error {
                Logger.media.error("Media sharing failed", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
            self?.currentActivityController = nil
            self?.clearSelection()
        }

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var currentController = rootViewController
            while let presented = currentController.presentedViewController {
                currentController = presented
            }
            currentController.present(activityViewController, animated: true)
        }
    }

    // MARK: - Observers

    private func setupObservers() {
        authorizationRepository.isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthorized in
                if !isAuthorized {
                    self?.showDeleteConfirmation = false
                    self?.showDecoyLimitWarning = false
                    self?.showDecoyConfirmation = false
                    self?.currentActivityController?.dismiss(animated: false)
                    self?.currentActivityController = nil
                    self?.mediaItems.removeAll()
                }
            }
            .store(in: &cancellables)
    }
}

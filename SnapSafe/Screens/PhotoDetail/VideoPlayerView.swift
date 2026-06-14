//
//  VideoPlayerView.swift
//  SnapSafe
//
//  Created by Claude on 1/26/26.
//

import SwiftUI
import AVKit
import Combine
import CryptoKit
import FactoryKit
import Logging

/// Video player view for playing both encrypted and unencrypted videos.
struct VideoPlayerView: View {
    @StateObject private var viewModel: VideoPlayerViewModel
    @EnvironmentObject private var nav: AppNavigationState

    init(videoDef: VideoDef, encryptionKey: SymmetricKey?) {
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(videoDef: videoDef, encryptionKey: encryptionKey))
    }

    var body: some View {
        ZStack {
            // Black background fills entire screen including safe area
            Color.black.ignoresSafeArea()

            // Video player fills screen
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onDisappear {
                        viewModel.cleanup()
                    }
            } else if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if let error = viewModel.error {
                ErrorView(error: error, onRetry: {
                    viewModel.retryPlayback()
                })
            }

            // Overlay controls - respects safe area
            VStack {
                // Top bar with back button
                HStack {
                    Button(action: {
                        viewModel.cleanup()
                        nav.navigateBack()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .padding(.leading)

                    Spacer()
                }
                .padding(.top, 8)

                Spacer()

                // Bottom controls
                if viewModel.showControls {
                    HStack {
                        Button(action: {
                            viewModel.togglePlayback()
                        }) {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                                .padding()
                        }

                        if let duration = viewModel.duration {
                            ProgressView(value: viewModel.currentTime, total: duration)
                                .tint(.white)
                                .frame(height: 4)
                                .padding(.horizontal)
                        }

                        if let duration = viewModel.duration {
                            Text("\(viewModel.currentTime.formattedTime) / \(duration.formattedTime)")
                                .foregroundStyle(.white)
                                .font(.caption)
                                .monospacedDigit()
                                .padding(.trailing)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.5))
                    .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut, value: viewModel.showControls)
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isPlaying)
        }
        .onTapGesture {
            viewModel.toggleControls()
        }
        .onAppear {
            viewModel.setupPlayback()
        }
        .navigationBarHidden(true)
    }

    // Helper view for error display
    private struct ErrorView: View {
        let error: Error
        let onRetry: () -> Void

        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white)
                
                Text("Playback Error")
                    .font(.title)
                    .foregroundStyle(.white)
                
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                
                Button(action: onRetry) {
                    Text("Retry")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    let videoDef: VideoDef
    let encryptionKey: SymmetricKey?

    @Injected(\.secureImageRepository) private var secureImageRepository: SecureImageRepository
    @Injected(\.addDecoyVideoUseCase) private var addDecoyVideoUseCase: AddDecoyVideoUseCase
    @Injected(\.videoEncryptionService) private var videoEncryptionService: VideoEncryptionService
    @Injected(\.pinRepository) private var pinRepository: PinRepository

    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var isPlaying = false
    @Published var showControls = true
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval? = nil
    @Published var error: Error? = nil
    @Published var isScrubbing = false
    /// True once the video has played to the end, so the transport can show a
    /// replay affordance instead of play/pause.
    @Published var didPlayToEnd = false
    @Published var isMuted = false

    // Gallery action state (used by the inline detail player)
    @Published var isPoisonPillConfigured = false
    @Published var isDecoy = false
    @Published var isDecoyOperationLoading = false

    var decoyButtonTitle: String { isDecoy ? "Remove Decoy" : "Add Decoy" }
    var decoyButtonIcon: String { isDecoy ? "shield.slash" : "shield" }

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var hideControlsTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private let controlsAutoHideDelay: TimeInterval = 5

    init(videoDef: VideoDef, encryptionKey: SymmetricKey?) {
        self.videoDef = videoDef
        self.encryptionKey = encryptionKey
    }

    // cleanup() is called from onDisappear in VideoPlayerView

    // MARK: - Public Methods

    func setupPlayback() {
        // A loader is already in flight or has finished — don't stack a
        // second AVPlayer that would race the first.
        guard player == nil, loadTask == nil else { return }

        // Use `.playback`/`.moviePlayback` so the video plays audibly even
        // when the phone's ringer switch is in silent — matching the Photos
        // app. Without this we inherit the iOS default `.soloAmbient`, which
        // respects the silent switch and produces a silent playback that
        // reads as "no audio was recorded."
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            logger.warning("Failed to configure audio session for playback", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }

        loadTask = Task { [weak self] in
            await self?.loadVideoAsset()
            await MainActor.run { self?.loadTask = nil }
        }
    }

    func cleanup() {
        hideControlsTask?.cancel()
        hideControlsTask = nil
        // Cancel any in-flight asset load so a slow decrypt can't auto-play
        // after the page has been swiped away.
        loadTask?.cancel()
        loadTask = nil
        cancellables.removeAll()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        player?.pause()
        isPlaying = false
        player = nil

        // Hand the audio session back so other audio (Music, podcasts) can
        // resume. Best-effort: log and move on if iOS refuses.
        do {
            try AVAudioSession.sharedInstance().setActive(
                false, options: [.notifyOthersOnDeactivation]
            )
        } catch {
            logger.debug("Audio session deactivate failed", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }

    func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying = !isPlaying
        didPlayToEnd = false
        scheduleHideControls()
    }

    /// Restarts playback from the beginning. Used by the replay affordance the
    /// transport shows once the video has played to the end.
    func replay() {
        guard let player else { return }
        didPlayToEnd = false
        player.seek(to: .zero)
        player.play()
        isPlaying = true
        scheduleHideControls()
    }

    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        scheduleHideControls()
    }

    func retryPlayback() {
        error = nil
        isLoading = true
        setupPlayback()
    }

    func toggleControls() {
        showControls.toggle()
        if showControls {
            scheduleHideControls()
        } else {
            hideControlsTask?.cancel()
        }
    }

    /// Shows the controls and (re)starts the auto-hide countdown. Call this
    /// whenever the user interacts with the controls so they stay visible
    /// long enough to be useful.
    func showAndScheduleHideControls() {
        if !showControls {
            withAnimation(.easeInOut(duration: 0.2)) {
                showControls = true
            }
        }
        scheduleHideControls()
    }

    /// Cancels any pending auto-hide. Use while the user is actively
    /// scrubbing so controls don't vanish mid-drag.
    func cancelHideControls() {
        hideControlsTask?.cancel()
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        let delay = controlsAutoHideDelay
        hideControlsTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.showControls, self.isPlaying, !self.isScrubbing else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.showControls = false
            }
        }
    }

    // MARK: - Private Methods

    private func loadVideoAsset() async {
        do {
            let asset: AVAsset
            
            if videoDef.isEncrypted {
                guard let encryptionKey = encryptionKey else {
                    throw SECVError.decryptionFailed
                }
                
                guard let encryptedAsset = AVAsset.makeEncryptedVideoAsset(with: videoDef.videoFile, encryptionKey: encryptionKey) else {
                    throw SECVError.decryptionFailed
                }
                
                asset = encryptedAsset
            } else {
                // For unencrypted videos, use regular AVAsset
                asset = AVURLAsset(url: videoDef.videoFile)
            }
            
            // Load asset metadata
            await loadAssetMetadata(asset)
            
            // Create player item and player
            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            
            // Setup time observer
            setupTimeObserver(for: player)
            
            // Setup player item observers
            setupPlayerItemObservers(for: playerItem)
            
            // Bail if the page was swiped away (or the model torn down)
            // while we were decrypting / loading — otherwise we'd attach a
            // fresh player and play audio off-screen.
            if Task.isCancelled {
                player.pause()
                return
            }

            // Update state
            await MainActor.run {
                guard !Task.isCancelled else {
                    player.pause()
                    return
                }
                self.player = player
                self.isLoading = false
                // Carry the current mute state onto the freshly created player.
                player.isMuted = self.isMuted

                let autoPlay = UserDefaults.standard.object(forKey: "autoPlayVideos") as? Bool ?? false
                if autoPlay {
                    player.play()
                    self.isPlaying = true
                } else {
                    self.isPlaying = false
                }
                self.scheduleHideControls()
            }
            
        } catch {
            await MainActor.run {
                self.error = error
                self.isLoading = false
                logger.error("Failed to load video asset", metadata: [
                    "error": .string(error.localizedDescription)
                ])
            }
        }
    }

    private func loadAssetMetadata(_ asset: AVAsset) async {
        do {
            // Load duration
            let duration = try await asset.load(.duration)
            await MainActor.run {
                self.duration = duration.seconds
            }
            
            // Load other metadata as needed
            let tracks = try await asset.load(.tracks)
            logger.debug("Video asset loaded", metadata: [
                "duration": .stringConvertible(duration.seconds),
                "trackCount": .stringConvertible(tracks.count)
            ])
            
        } catch {
            logger.error("Failed to load asset metadata", metadata: [
                "error": .string(error.localizedDescription)
            ])
        }
    }

    private func setupTimeObserver(for player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, !self.isScrubbing else { return }
                self.currentTime = time.seconds
            }
        }
    }

    private func setupPlayerItemObservers(for playerItem: AVPlayerItem) {
        // Observe playback status
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self = self else { return }
                
                switch status {
                case .readyToPlay:
                    self.isLoading = false
                    logger.debug("Player item ready to play")
                    
                case .failed:
                    if let error = playerItem.error {
                        self.error = error
                        logger.error("Player item failed", metadata: [
                            "error": .string(error.localizedDescription)
                        ])
                    }
                    
                case .unknown:
                    logger.debug("Player item status unknown")
                    
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Observe playback completion
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.isPlaying = false
                self.didPlayToEnd = true
                self.showControls = true
                logger.debug("Playback completed")
            }
            .store(in: &cancellables)
    }

    // MARK: - Scrubbing

    func beginScrubbing() {
        isScrubbing = true
        player?.pause()
        cancelHideControls()
    }

    /// Updates the displayed time as the user drags, without committing a seek.
    func scrub(toFraction fraction: Double) {
        guard let duration else { return }
        currentTime = max(0, min(duration, duration * fraction))
    }

    /// Commits the seek and resumes playback if it was playing.
    func endScrubbing(atFraction fraction: Double) {
        guard let duration, let player else { isScrubbing = false; return }
        let target = max(0, min(duration, duration * fraction))
        currentTime = target
        if target < duration { didPlayToEnd = false }
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isScrubbing = false
                if self.isPlaying { self.player?.play() }
                self.scheduleHideControls()
            }
        }
    }

    // MARK: - Gallery Actions (inline detail player)

    func loadActionState() {
        Task {
            let decoy = await secureImageRepository.isDecoyVideo(videoDef)
            let configured = await pinRepository.hasPoisonPillPin()
            await MainActor.run {
                self.isDecoy = decoy
                self.isPoisonPillConfigured = configured
            }
        }
    }

    func toggleDecoy() {
        isDecoyOperationLoading = true
        Task {
            if isDecoy {
                _ = await secureImageRepository.removeDecoyVideo(videoDef)
                await MainActor.run {
                    self.isDecoy = false
                    self.isDecoyOperationLoading = false
                }
            } else {
                let success = await addDecoyVideoUseCase.addDecoyVideo(videoDef: videoDef)
                await MainActor.run {
                    self.isDecoy = success
                    self.isDecoyOperationLoading = false
                }
                if !success { logger.error("Failed to add video decoy") }
            }
        }
    }

    func share() {
        Task {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("share_\(videoDef.videoName).mov")
            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            do {
                if videoDef.isEncrypted, let key = encryptionKey {
                    try await videoEncryptionService.decryptVideoForSharing(
                        inputURL: videoDef.videoFile, outputURL: tempURL, encryptionKey: key)
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: videoDef.videoFile, to: tempURL)
                }
                await MainActor.run { self.presentShareSheet(with: [tempURL]) }
            } catch {
                logger.error("Failed to prepare video for sharing", metadata: [
                    "error": .string(error.localizedDescription)])
            }
        }
    }

    /// Deletes the video and its derived files. The caller dismisses the detail view.
    func deleteVideo() {
        cleanup()
        try? FileManager.default.removeItem(at: videoDef.videoFile)
        Task {
            await secureImageRepository.deleteVideoThumbnail(forVideoNamed: videoDef.videoName)
            _ = await secureImageRepository.removeDecoyVideo(videoDef)
        }
    }

    private func presentShareSheet(with items: [Any]) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = ac.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                        y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(ac, animated: true)
    }

    private let logger = Logger.video
}

// MARK: - TimeInterval Extension

extension TimeInterval {
    var formattedTime: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// NOTE: AVPlayerItem status observation uses Foundation's built-in, thread-safe
// `NSObject.publisher(for:options:)` (default options `[.initial, .new]`). A custom
// Combine `Publisher`/`Subscription` used to live here, but it was `@unchecked
// Sendable` and mutated its subscription state in `cancel()` without synchronization
// while the KVO callback could fire concurrently — a data race. The built-in KVO
// publisher provides the same semantics safely.

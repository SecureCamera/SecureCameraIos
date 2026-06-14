//
//  InlineVideoPlayerView.swift
//  SnapSafe
//
//  A full glass-native video page for the detail pager: a bare AVPlayerLayer
//  surface with our own transport controls (play/pause, scrubber, time) and the
//  glass action toolbar (Share/Decoy/Delete) stacked together at the bottom, so
//  nothing overlaps. AVKit's built-in controls are not used.
//

import SwiftUI
import AVKit
import CryptoKit

struct InlineVideoPlayerView: View {
    /// Called when the video is deleted, so the parent can pop the detail view.
    let onRequestDismiss: () -> Void
    /// Reports glass-control visibility so the page-level photo counter chip
    /// can fade in/out alongside the video transport.
    var onControlsVisibilityChange: ((Bool) -> Void)? = nil
    /// Shared with the pager: true while the video is pinch-zoomed, which
    /// disables paging and the dismiss drag (same contract as photo pages).
    @Binding internal var isZoomed: Bool

    /// Pager-level chrome state; nil outside the pager (e.g. previews).
    @Environment(PagerChromeState.self) private var chrome: PagerChromeState?

    private var isChromeSuppressed: Bool { chrome?.isDismissDragging ?? false }

    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var scrubFraction: Double = 0
    @State private var showDeleteConfirmation = false

    init(
        videoDef: VideoDef,
        encryptionKey: SymmetricKey?,
        isZoomed: Binding<Bool> = .constant(false),
        onRequestDismiss: @escaping () -> Void,
        onControlsVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self._isZoomed = isZoomed
        self.onRequestDismiss = onRequestDismiss
        self.onControlsVisibilityChange = onControlsVisibilityChange
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(videoDef: videoDef, encryptionKey: encryptionKey))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                // Video area — fills the space above the action bar. The
                // transport bar overlays its bottom edge (may overlap the
                // last sliver of the frame, which is acceptable).
                ZStack {
                    Group {
                        if let player = viewModel.player {
                            ZoomableScrollView(
                                minZoom: 1.0,
                                maxZoom: 6.0,
                                isZoomed: $isZoomed,
                                onSingleTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.toggleControls()
                                    }
                                }
                            ) {
                                VideoSurfaceView(player: player)
                            }
                        } else if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        } else if viewModel.error != nil {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("Could not play video")
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if viewModel.showControls && !isChromeSuppressed {
                        VStack {
                            Spacer()
                            VideoTransportBar(
                                isPlaying: viewModel.isPlaying,
                                didPlayToEnd: viewModel.didPlayToEnd,
                                isMuted: viewModel.isMuted,
                                currentTime: viewModel.currentTime,
                                duration: viewModel.duration,
                                fraction: $scrubFraction,
                                onPlayPause: { viewModel.togglePlayback() },
                                onReplay: { viewModel.replay() },
                                onToggleMute: { viewModel.toggleMute() },
                                onScrubBegan: { viewModel.beginScrubbing() },
                                onScrubEnded: { viewModel.endScrubbing(atFraction: scrubFraction) }
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
                .ignoresSafeArea(edges: .top)

                // Action bar — sits BELOW the video area, never overlapping it.
                // Use opacity (not conditional rendering) for the dismiss-drag
                // fade so the VStack doesn't reflow mid-drag; reflow would race
                // the offset update and make the video frame shake.
                if viewModel.showControls {
                    VideoDetailToolbar(
                        onShare: { viewModel.share() },
                        onDelete: { showDeleteConfirmation = true },
                        onToggleDecoy: { viewModel.toggleDecoy() },
                        showDecoyButton: viewModel.isPoisonPillConfigured,
                        decoyButtonTitle: viewModel.decoyButtonTitle,
                        decoyButtonIcon: viewModel.decoyButtonIcon,
                        isDecoyOperationLoading: viewModel.isDecoyOperationLoading
                    )
                    .opacity(isChromeSuppressed ? 0 : 1)
                    .allowsHitTesting(!isChromeSuppressed)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isChromeSuppressed)
        .onChange(of: scrubFraction) { _, fraction in
            if viewModel.isScrubbing { viewModel.scrub(toFraction: fraction) }
        }
        .onChange(of: viewModel.currentTime) { _, _ in
            guard !viewModel.isScrubbing, let duration = viewModel.duration, duration > 0 else { return }
            scrubFraction = viewModel.currentTime / duration
        }
        .onAppear {
            viewModel.setupPlayback()
            viewModel.loadActionState()
            viewModel.showAndScheduleHideControls()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onChange(of: viewModel.showControls, initial: true) { _, visible in
            onControlsVisibilityChange?(visible)
        }
        .alert("Delete Video", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.deleteVideo()
                onRequestDismiss()
            }
        } message: {
            Text("Are you sure you want to delete this video? This action cannot be undone.")
        }
        .alert("Decoy Limit Reached", isPresented: $viewModel.showDecoyLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can have a maximum of 10 decoy items. Remove an existing decoy before adding a new one.")
        }
    }
}

// MARK: - Transport bar

private struct VideoTransportBar: View {
    let isPlaying: Bool
    let didPlayToEnd: Bool
    let isMuted: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval?
    @Binding var fraction: Double
    let onPlayPause: () -> Void
    let onReplay: () -> Void
    let onToggleMute: () -> Void
    let onScrubBegan: () -> Void
    let onScrubEnded: () -> Void

    private var leadingIcon: String {
        if didPlayToEnd { return "arrow.counterclockwise" }
        return isPlaying ? "pause.fill" : "play.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: didPlayToEnd ? onReplay : onPlayPause) {
                Image(systemName: leadingIcon)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didPlayToEnd ? "Replay" : (isPlaying ? "Pause" : "Play"))

            Text(currentTime.formattedTime)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.primary)

            Slider(value: $fraction, in: 0...1) { editing in
                if editing { onScrubBegan() } else { onScrubEnded() }
            }
            .tint(.primary)

            Text((duration ?? 0).formattedTime)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.7))

            Button(action: onToggleMute) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMuted ? "Unmute" : "Mute")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassTransportBackground()
        .padding(.horizontal, 24)
        .sensoryFeedback(.impact(weight: .light), trigger: isPlaying)
    }
}

private extension View {
    @ViewBuilder
    func glassTransportBackground() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
                .environment(\.colorScheme, .dark)
        } else {
            self.background(.ultraThinMaterial, in: .capsule)
                .environment(\.colorScheme, .dark)
        }
    }
}

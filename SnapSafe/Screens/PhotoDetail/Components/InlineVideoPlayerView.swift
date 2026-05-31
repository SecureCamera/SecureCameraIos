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
    let videoDef: VideoDef
    let encryptionKey: SymmetricKey?
    /// Called when the video is deleted, so the parent can pop the detail view.
    let onRequestDismiss: () -> Void
    /// Reports glass-control visibility so the page-level photo counter chip
    /// can fade in/out alongside the video transport.
    var onControlsVisibilityChange: ((Bool) -> Void)? = nil

    @StateObject private var viewModel: VideoPlayerViewModel
    @State private var scrubFraction: Double = 0
    @State private var showDeleteConfirmation = false

    init(
        videoDef: VideoDef,
        encryptionKey: SymmetricKey?,
        onRequestDismiss: @escaping () -> Void,
        onControlsVisibilityChange: ((Bool) -> Void)? = nil
    ) {
        self.videoDef = videoDef
        self.encryptionKey = encryptionKey
        self.onRequestDismiss = onRequestDismiss
        self.onControlsVisibilityChange = onControlsVisibilityChange
        _viewModel = StateObject(wrappedValue: VideoPlayerViewModel(videoDef: videoDef, encryptionKey: encryptionKey))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video surface (or loading / error)
            Group {
                if let player = viewModel.player {
                    VideoSurfaceView(player: player)
                        .ignoresSafeArea()
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
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleControls()
                }
            }

            // Bottom control stack — transport above actions, one container so
            // the two glass bars can never overlap.
            VStack {
                Spacer()
                if viewModel.showControls {
                    VStack(spacing: 12) {
                        VideoTransportBar(
                            isPlaying: viewModel.isPlaying,
                            currentTime: viewModel.currentTime,
                            duration: viewModel.duration,
                            fraction: $scrubFraction,
                            onPlayPause: { viewModel.togglePlayback() },
                            onScrubBegan: { viewModel.beginScrubbing() },
                            onScrubEnded: { viewModel.endScrubbing(atFraction: scrubFraction) }
                        )

                        VideoDetailToolbar(
                            onShare: { viewModel.share() },
                            onDelete: { showDeleteConfirmation = true },
                            onToggleDecoy: { viewModel.toggleDecoy() },
                            showDecoyButton: viewModel.isPoisonPillConfigured,
                            decoyButtonTitle: viewModel.decoyButtonTitle,
                            decoyButtonIcon: viewModel.decoyButtonIcon,
                            isDecoyOperationLoading: viewModel.isDecoyOperationLoading
                        )
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
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
    }
}

// MARK: - Transport bar

private struct VideoTransportBar: View {
    let isPlaying: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval?
    @Binding var fraction: Double
    let onPlayPause: () -> Void
    let onScrubBegan: () -> Void
    let onScrubEnded: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Text(currentTime.formattedTime)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white)

            Slider(value: $fraction, in: 0...1) { editing in
                if editing { onScrubBegan() } else { onScrubEnded() }
            }
            .tint(.white)

            Text((duration ?? 0).formattedTime)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
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
        } else {
            self.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

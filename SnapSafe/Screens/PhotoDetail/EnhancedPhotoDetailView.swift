//
//  EnhancedPhotoDetailView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/26/25.
//

import Foundation
import SwiftUI
import Logging


internal struct DismissTransformModifier: ViewModifier {
    internal let isZoomed: Bool
    internal let scale: CGFloat
    internal let verticalOffset: CGFloat

    internal func body(content: Content) -> some View {
        content
            .scaleEffect(isZoomed ? 1.0 : scale)
            .offset(y: isZoomed ? 0 : verticalOffset)
    }
}

internal extension View {
    func dismissTransform(
        isZoomed: Bool,
        scale: CGFloat,
        verticalOffset: CGFloat
    ) -> some View {
        modifier(
            DismissTransformModifier(
                isZoomed: isZoomed,
                scale: scale,
                verticalOffset: verticalOffset
            )
        )
    }
}

internal struct PhotoCounterChip: View {
    internal let text: String
    internal let opacity: Double

    internal var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .clipShape(.rect(cornerRadius: 12))
                .opacity(opacity)
            Spacer()
        }
        .padding(.top, 50)
    }
}

struct EnhancedPhotoDetailView: View {
    @StateObject private var viewModel: EnhancedPhotoDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nav: AppNavigationState

    init(
        allMedia: [GalleryMediaItem],
        initialIndex: Int,
        onDelete: ((PhotoDef) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: EnhancedPhotoDetailViewModel(
                allMedia: allMedia,
                initialIndex: initialIndex,
                onDelete: onDelete,
                onDismiss: onDismiss
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .opacity(viewModel.backgroundOpacity)
                    .ignoresSafeArea()

                // UIKit-based paging with proper gesture coordination
                PhotoPageViewController(
                    allMedia: viewModel.allMedia,
                    currentIndex: $viewModel.currentIndex,
                    isZoomed: $viewModel.isZoomed
                )
                .onChange(of: viewModel.currentIndex) { _, newIndex in
                    viewModel.handleIndexChange(newIndex: newIndex)
                }
                // Apply the dismiss transform via a tiny modifier
                .dismissTransform(
                    isZoomed: viewModel.isZoomed,
                    scale: viewModel.photoScaleEffect,
                    verticalOffset: viewModel.dragOffset.height
                )

                // Bottom toolbar — shown only for photos; videos have AVKit controls
                VStack {
                    Spacer()
                    if !viewModel.currentIsVideo, viewModel.currentIndex < viewModel.allMedia.count {
                        PhotoControlsView(
                            onInfo: {
                                if let current = viewModel.currentPhotoDef {
                                    nav.presentSheet(.photoInfo(current))
                                }
                            },
                            onObfuscate: {
                                if let current = viewModel.currentPhotoDef {
                                    nav.navigate(to: .photoObfuscation(current))
                                }
                            },
                            onShare: { viewModel.shareCurrentPhoto() },
                            onDelete: { viewModel.showDeleteConfirmation = true },
                            onToggleDecoy: { viewModel.toggleDecoyStatus() },
                            isZoomed: viewModel.isZoomed,
                            showDecoyButton: viewModel.isPoisonPillConfigured,
                            decoyButtonTitle: viewModel.decoyButtonTitle,
                            decoyButtonIcon: viewModel.decoyButtonIcon,
                            isDecoyOperationLoading: viewModel.isDecoyOperationLoading
                        )
                        .padding(.bottom, 8)
                    }
                }

                // Counter overlay
                VStack {
                    PhotoCounterChip(
                        text: viewModel.currentPhotoDisplayText,
                        opacity: viewModel.overlayOpacity
                    )
                    Spacer()
                }
            }
            // Vertical dismiss gesture (gated inside handlers)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard viewModel.mayDismissByDrag() else { return }
                        viewModel.handleDragChanged(
                            value,
                            geometryHeight: geometry.size.height
                        )
                    }
                    .onEnded { value in
                        guard viewModel.mayDismissByDrag() else { return }
                        viewModel.handleDragEnded(
                            value,
                            geometryHeight: geometry.size.height
                        ) { dismiss() }
                    }
            )
        }
        .navigationBarHidden(true)
        .supportedOrientations(.allButUpsideDown)
        .onAppear { viewModel.onAppear() }
        .alert(
            "Delete Photo",
            isPresented: $viewModel.showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    viewModel.deletePhoto(at: viewModel.currentIndex)
                    dismiss()
                }
            },
            message: {
                Text("Are you sure you want to delete this photo? This action cannot be undone.")
            }
        )
    }
}

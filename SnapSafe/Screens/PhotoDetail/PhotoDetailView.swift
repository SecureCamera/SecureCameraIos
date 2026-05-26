//
//  PhotoDetailView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import Logging

struct PhotoDetailView: View {
    // ViewModel
    @StateObject private var viewModel: PhotoDetailViewModel

    // Environment
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nav: AppNavigationState

    // Zoom state binding (shared with parent)
    @Binding var isZoomed: Bool

    // Initialize with a single photo
    init(photo: PhotoDef, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil, isZoomed: Binding<Bool> = .constant(false)) {
        _viewModel = StateObject(wrappedValue: PhotoDetailViewModel(
            photo: photo,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
        _isZoomed = isZoomed
    }

    // Initialize with multiple photos
    init(allPhotos: [PhotoDef], initialIndex: Int, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil, isZoomed: Binding<Bool> = .constant(false)) {
        _viewModel = StateObject(wrappedValue: PhotoDetailViewModel(
            allPhotos: allPhotos,
            initialIndex: initialIndex,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
        _isZoomed = isZoomed
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.opacity(0.05)
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // Photo counter at the top if we have multiple photos
                    if !viewModel.photoFiles.isEmpty {
                        Text("\(viewModel.currentIndex + 1) of \(viewModel.photoFiles.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .opacity(isZoomed ? 0.5 : 1.0) // Fade when zoomed
                    }

                    // Zoom level indicator
                    ZoomLevelIndicator(
                        scale: viewModel.currentScale,
                        isVisible: isZoomed
                    )
                    // Centered image display with native UIScrollView zoom/pan
                    if viewModel.isImageLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ZoomableScrollView(
                            minZoom: 1.0,
                            maxZoom: 6.0,
                            isZoomed: $isZoomed
                        ) {
                            Image(uiImage: viewModel.displayedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .rotationEffect(Angle(radians: viewModel.imageRotation))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationBarTitle("Photo Detail", displayMode: .inline)
            .alert(
                "Delete Photo",
                isPresented: $viewModel.showDeleteConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        viewModel.deleteCurrentPhoto()
                        dismiss()
                    }
                },
                message: {
                    Text("Are you sure you want to delete this photo? This action cannot be undone.")
                }
            )
            .sheet(isPresented: $viewModel.showImageInfo) {
                if let photoDef = viewModel.currentPhotoDef {
                    ImageInfoView(photoDef: photoDef)
                }
            }
            .onAppear {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }
    }
}

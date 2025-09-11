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

// Use a different name to avoid conflicts with the top-level typealias
struct PhotoDetailView: View {
    // ViewModel
    @StateObject private var viewModel: PhotoDetailViewModel
    
    // Environment
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nav: AppNavigationState
    
    // Initialize with a single photo
    init(photo: PhotoDef, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoDetailViewModel(
            photo: photo,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
    }
    
    // Initialize with multiple photos
    init(allPhotos: [PhotoDef], initialIndex: Int, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoDetailViewModel(
            allPhotos: allPhotos,
            initialIndex: initialIndex,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Color.black.opacity(0.05)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    // Photo counter at the top if we have multiple photos
                    if !viewModel.photoFiles.isEmpty {
                        Text("\(viewModel.currentIndex + 1) of \(viewModel.photoFiles.count)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .opacity(viewModel.isZoomed ? 0.5 : 1.0) // Fade when zoomed
                    }
                    
                    Spacer()
                    
                    // Zoom level indicator
                    ZoomLevelIndicator(
                        scale: viewModel.currentScale,
                        isVisible: viewModel.isZoomed
                    )
                    
                    // Centered image display with appropriate orientation handling
                    if viewModel.isImageLoading {
                        ProgressView("Loading...")
                            .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.7)
                    } else {
                        ZoomableImageView(
                            image: viewModel.displayedImage,
                            geometrySize: geometry.size,
                            canGoToPrevious: viewModel.canGoToPrevious,
                            canGoToNext:     viewModel.canGoToNext,
                            onNavigatePrevious: viewModel.navigateToPrevious,
                            onNavigateNext:     viewModel.navigateToNext,
                            onDismiss: {
                                viewModel.onDisappear()
                                dismiss()
                            },
                            imageRotation:        viewModel.imageRotation,
                            isFaceDetectionActive: false
                        ) {
                            // No overlay needed - face detection is in separate screen
                            EmptyView()
                        }
                        .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.7)
                    }
                    
                    Spacer()
                    
                    // Photo controls
                    PhotoControlsView(
                        onInfo: { viewModel.showImageInfo = true },
                        onObfuscate: {
                            // Navigate to obfuscation screen
                            if let currentPhotoDef = viewModel.currentPhotoDef {
                                //nav.navigate(to: .photoObfuscation(currentPhotoDef))
                                nav.presentedFullScreenCover = .photoObfuscation(currentPhotoDef)
                            }
                        },
                        onShare: {
                            Logger.ui.debug("Share button pressed - showing share sheet")
                            viewModel.sharePhoto()
                        },
                        onDelete: {
                            Logger.ui.debug("Delete button pressed - showing confirmation")
                            viewModel.showDeleteConfirmation = true
                        },
                        isZoomed: viewModel.isZoomed
                    )
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
        .securityManaged()
    }
    
    // No additional helpers needed now
}

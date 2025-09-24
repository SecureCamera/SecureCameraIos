//
//  EnhancedPhotoDetailView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/26/25.
//

import SwiftUI

struct EnhancedPhotoDetailView: View {
    @StateObject private var viewModel: EnhancedPhotoDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nav: AppNavigationState

    // Store PhotoDetailViewModels for toolbar access
    @State private var photoDetailViewModels: [PhotoDetailViewModel] = []

    init(allPhotos: [PhotoDef], initialIndex: Int, onDelete: ((PhotoDef) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: EnhancedPhotoDetailViewModel(
            allPhotos: allPhotos,
            initialIndex: initialIndex,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background that fades during dismiss
                Color.black
                    .opacity(viewModel.backgroundOpacity)
                    .edgesIgnoringSafeArea(.all)

                TabView(selection: $viewModel.currentIndex) {
                    ForEach(Array(viewModel.photoFiles.enumerated()), id: \.offset) { index, photoDef in
                        PhotoDetailView(
                            photo: photoDef,
                            onDelete: { photoDef in
                                viewModel.onDelete?(photoDef)
                            },
                            onDismiss: {}
                        )
                        .tag(index)
                        .scaleEffect(viewModel.photoScaleEffect)
                        .offset(y: viewModel.dragOffset.height)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .onChange(of: viewModel.currentIndex) { _, newIndex in
                    viewModel.handleIndexChange(newIndex: newIndex)
                }
                .safeAreaInset(edge: .bottom) {
                    // Fixed toolbar - outside of swipeable content
                    if viewModel.currentIndex < viewModel.photoFiles.count {
                        PhotoControlsView(
                            onInfo: {
                                viewModel.showImageInfo = true
                            },
                            onObfuscate: {
                                // Navigate to obfuscation screen
                                if let currentPhotoDef = viewModel.currentPhotoDef {
                                    nav.presentedFullScreenCover = .photoObfuscation(currentPhotoDef)
                                }
                            },
                            onShare: {
                                viewModel.shareCurrentPhoto()
                            },
                            onDelete: {
                                viewModel.showDeleteConfirmation = true
                            },
                            onToggleDecoy: {
                                viewModel.toggleDecoyStatus()
                            },
                            isZoomed: false, // We don't have zoom state at this level yet
                            showDecoyButton: viewModel.isPoisonPillConfigured,
                            decoyButtonTitle: viewModel.decoyButtonTitle,
                            decoyButtonIcon: viewModel.decoyButtonIcon,
                            isDecoyOperationLoading: viewModel.isDecoyOperationLoading
                        )
                    }
                }

                // Photo counter overlay
                VStack {
                    HStack {
                        Spacer()
                        Text(viewModel.currentPhotoDisplayText)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(12)
                            .opacity(viewModel.overlayOpacity)
                        Spacer()
                    }
                    .padding(.top, 50)

                    Spacer()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.handleDragChanged(value, geometryHeight: geometry.size.height)
                    }
                    .onEnded { value in
                        viewModel.handleDragEnded(value, geometryHeight: geometry.size.height) {
                            dismiss()
                        }
                    }
            )
        }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.onAppear()
        }
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
        .sheet(isPresented: $viewModel.showImageInfo) {
            if let photoDef = viewModel.currentPhotoDef {
                ImageInfoView(photoDef: photoDef)
            }
        }
    }
}

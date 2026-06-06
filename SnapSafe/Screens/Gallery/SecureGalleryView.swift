//
//  SecureGalleryView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import PhotosUI
import SwiftUI
import Logging
import CryptoKit
import FactoryKit


// Empty state view when no media exist
struct EmptyGalleryView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Text("No photos yet")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Gallery is empty. Use the camera to take your first photo.")
        }
    }
}


// Gallery view to display stored photos and videos
struct SecureGalleryView: View {
    @AppStorage("showFaceDetection") private var showFaceDetection = true
    @StateObject private var viewModel: MixedMediaGalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var nav: AppNavigationState

    let onDismiss: (() -> Void)?

    // Standard initializer
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: MixedMediaGalleryViewModel())
    }

    // Initializer for decoy selection mode
    init(selectingDecoys: Bool, onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: MixedMediaGalleryViewModel(selectingDecoys: selectingDecoys))
    }


    var body: some View {
        ZStack {
            Group {
                if viewModel.mediaItems.isEmpty {
                    EmptyGalleryView(onDismiss: {
                        if let onDismiss { onDismiss() } else { dismiss() }
                    })
                } else {
                    mediaGridView
                }
            }

            // Import progress overlay
            if viewModel.isImporting {
                VStack {
                    ProgressView("Importing photos...", value: viewModel.importProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding()

                    Text("\(Int(viewModel.importProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 200)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemBackground))
                        .shadow(radius: 5)
                )
            }

            // Decoy save / re-encryption overlay
            if viewModel.isSavingDecoys {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Saving decoy media…")
                        .font(.callout)

                    if viewModel.decoySaveTotal > 1 {
                        Text("\(viewModel.decoySaveCompleted) of \(viewModel.decoySaveTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(radius: 5)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Saving decoy media")
            }
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Back button in the leading position (only for decoy selection mode)
            if viewModel.isSelectingDecoys {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        viewModel.exitDecoyMode()
                        if let onDismiss { onDismiss() } else { dismiss() }
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .disabled(viewModel.isSavingDecoys)
                }
            }

            // Action buttons in the trailing position
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if viewModel.isSelectingDecoys {
                        Text(viewModel.decoyCountText)
                            .font(.caption)
                            .foregroundStyle(viewModel.decoyCountTextColor)

                        Button("Save") {
                            viewModel.showDecoyConfirmationAlert()
                        }
                        .foregroundStyle(.blue)
                        .disabled(viewModel.isSaveDecoyButtonDisabled)
                    } else if viewModel.isSelecting {
                        Button("Cancel") {
                            viewModel.cancelSelecting()
                        }
                        .foregroundStyle(.red)
                    } else {
                        Menu {
                            Button {
                                viewModel.startSelecting(mode: .share)
                            } label: {
                                Label("Select Items", systemImage: "checkmark.circle")
                            }

                            Button {
                                viewModel.startSelecting(mode: .delete)
                            } label: {
                                Label("Select to Delete", systemImage: "trash")
                            }

                            if viewModel.isPoisonPillConfigured {
                                Button {
                                    viewModel.startSelecting(mode: .decoy)
                                } label: {
                                    Label("Select for Decoys", systemImage: "shield")
                                }
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }

            // Bottom toolbar with main action buttons
            ToolbarItemGroup(placement: .bottomBar) {
                switch viewModel.selectionMode {
                case .none:
                    // Parameterless form: same out-of-process picker, but the
                    // binary carries no PHPhotoLibrary reference for App Store
                    // upload scanning to flag.
                    PhotosPicker(selection: $viewModel.pickerItems, matching: .any(of: [.images, .videos])) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .onChange(of: viewModel.pickerItems) { _, newItems in
                        viewModel.processPickerItems(newItems)
                    }

                    Spacer()

                case .share:
                    if viewModel.hasSelection {
                        Spacer()

                        Button(action: viewModel.shareSelectedMedia) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }

                case .delete:
                    if viewModel.hasSelection {
                        Button(action: {
                            Logger.ui.info("Delete button pressed in gallery view, selected items: \(viewModel.selectedMediaIds.count)")
                            viewModel.showDeleteAlert()
                        }) {
                            Label("Delete", systemImage: "trash")
                                .foregroundStyle(.red)
                        }

                        Spacer()
                    }

                case .decoy:
                    EmptyView()
                }
            }
        }
        .onAppear(perform: viewModel.onAppear)
        .onChange(of: viewModel.selectedMediaItem) { _, newValue in
            guard let item = newValue else { return }
            viewModel.selectedMediaItem = nil

            // Navigate into the mixed-media detail pager. Both photos and videos
            // are passed so the user can swipe between all items in the gallery.
            if let initialIndex = viewModel.mediaItems.firstIndex(where: { $0.id == item.id }) {
                nav.navigate(to: .photoDetail(allMedia: viewModel.mediaItems, initialIndex: initialIndex))
            }
        }
        .alert(
            viewModel.deleteAlertTitle,
            isPresented: $viewModel.showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Logger.ui.info("Delete confirmation button pressed, deleting \(viewModel.selectedMediaIds.count) items")
                    viewModel.deleteSelectedMedia()
                }
            },
            message: {
                Text(viewModel.deleteAlertMessage)
            }
        )
        .alert(
            "Too Many Decoys",
            isPresented: $viewModel.showDecoyLimitWarning,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(viewModel.decoyLimitWarningMessage)
            }
        )
        .alert(
            "Save Decoy Selection",
            isPresented: $viewModel.showDecoyConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task {
                        await viewModel.saveDecoySelections()
                        if let onDismiss { onDismiss() } else { dismiss() }
                    }
                }
            },
            message: {
                Text(viewModel.decoyConfirmationMessage)
            }
        )
    }

    // Mixed media grid subview
    private var mediaGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(viewModel.mediaItems) { item in
                    if let photoDef = item.photoDef {
                        PhotoCell(
                            photo: photoDef,
                            isSelected: viewModel.isSelected(item),
                            isSelecting: viewModel.isSelecting,
                            onTap: {
                                viewModel.handleMediaTap(item)
                            },
                            onDelete: {
                                viewModel.prepareToDeleteSingleMedia(item)
                            }
                        )
                    } else if item.mediaType == .video {
                        VideoCellView(
                            item: item,
                            isSelected: viewModel.isSelected(item),
                            isSelecting: viewModel.isSelecting,
                            onTap: {
                                viewModel.handleMediaTap(item)
                            }
                        )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Video Cell View

struct VideoCellView: View {
    let item: GalleryMediaItem
    let isSelected: Bool
    let isSelecting: Bool
    let onTap: () -> Void

    @Injected(\.secureImageRepository)
    private var secureImageRepository: SecureImageRepository

    @State private var thumbnail: UIImage? = nil
    @State private var isDecoy: Bool = false

    private let cellSize: CGFloat = 100

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Thumbnail (or placeholder while loading / when unavailable)
                ZStack {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color(.systemGray5)
                        Image(systemName: "video.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: cellSize, height: cellSize)
                .clipped()
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )

                // Play badge (top-trailing) marks the item as a video
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .padding(4)
                    }
                    Spacer()
                }

                // Decoy indicator (bottom-leading)
                if isDecoy {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "shield.fill")
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(5)
                            Spacer()
                        }
                    }
                }

                // Selection checkmark overlay
                if isSelecting {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .blue : .white)
                                .font(.title2)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                    }
                }
            }
            .frame(width: cellSize, height: cellSize)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Video: \(item.mediaName)")
        .accessibilityHint(isSelecting ? "Double-tap to \(isSelected ? "deselect" : "select")" : "Double-tap to open")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .task {
            if let videoDef = item.videoDef {
                thumbnail = await secureImageRepository.readVideoThumbnail(videoDef)
                isDecoy = secureImageRepository.isDecoyVideo(videoDef)
            }
        }
    }
}

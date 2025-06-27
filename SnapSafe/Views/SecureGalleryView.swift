//
//  SecureGalleryView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import PhotosUI
import SwiftUI

// Empty state view when no photos exist
struct EmptyGalleryView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Text("No photos yet")
                .font(.title)
                .foregroundColor(.secondary)
        }
    }
}

// Gallery view to display the stored photos
struct SecureGalleryView: View {
    @StateObject private var viewModel = SecureGalleryViewModel()
    @State private var selectedPhoto: SecurePhoto?
    @AppStorage("showFaceDetection") private var showFaceDetection = true // Using AppStorage to share with Settings
    @State private var pickerItems: [PhotosPickerItem] = []

    // Decoy selection mode
    @State private var isSelectingDecoys: Bool = false
    @State private var maxDecoys: Int = 10

    @Environment(\.dismiss) private var dismiss

    // Callback for dismissing the gallery
    let onDismiss: (() -> Void)?

    // Initializers
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    // Initializer for decoy selection mode
    init(selectingDecoys: Bool, onDismiss: (() -> Void)? = nil) {
        _isSelectingDecoys = State(initialValue: selectingDecoys)
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Group {
                if viewModel.photos.isEmpty {
                    EmptyGalleryView(onDismiss: {
                        onDismiss?()
                        dismiss()
                    })
                } else {
                    photosGridView
                }
            }

            // Import progress overlay
            if viewModel.isImporting {
                importProgressOverlay
            }
        }
        .navigationTitle(isSelectingDecoys ? "Select Decoy Photos" : "Secure Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Back button in the leading position
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if isSelectingDecoys {
                        // Exit decoy selection mode and return to settings
                        isSelectingDecoys = false
                        viewModel.cancelSelection()
                    }
                    onDismiss?()
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(.blue)
                }
            }

            // Action buttons in the trailing position (simplified for top toolbar)
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if isSelectingDecoys {
                        // Count label and Save button for decoy selection
                        Text("\(viewModel.selectedPhotoIds.count)/\(maxDecoys)")
                            .font(.caption)
                            .foregroundColor(viewModel.selectedPhotoIds.count > maxDecoys ? .red : .secondary)

                        Button("Save") {
                            if !viewModel.validateDecoySelection() {
                                viewModel.showDecoyLimitWarning = true
                            } else {
                                viewModel.showDecoyConfirmation = true
                            }
                        }
                        .foregroundColor(.blue)
                        .disabled(viewModel.selectedPhotoIds.isEmpty)
                    } else if viewModel.isSelecting {
                        // Cancel selection button
                        Button("Cancel") {
                            viewModel.cancelSelection()
                        }
                        .foregroundColor(.red)
                    } else {
                        // Context menu with Select and Filter options
                        Menu {
                            Button("Select Photos") {
                                viewModel.startSelection()
                            }

                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .toolbar {
            // Bottom toolbar with main action buttons
            ToolbarItemGroup(placement: .bottomBar) {
                if !isSelectingDecoys, !viewModel.isSelecting {
                    // Normal mode: Import button
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .onChange(of: pickerItems) { _, newItems in
                        viewModel.processPhotoImport(from: newItems)
                        pickerItems = []
                    }

                    Spacer()
                } else if viewModel.isSelecting, viewModel.hasSelection, !isSelectingDecoys {
                    // Selection mode: Delete and Share buttons
                    Button(action: {
                        print("Delete button pressed in gallery view, selected photos: \(viewModel.selectedPhotoIds.count)")
                        viewModel.showDeleteConfirmation = true
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }

                    Spacer()

                    Button(action: viewModel.shareSelectedPhotos) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            viewModel.loadPhotos()
            if isSelectingDecoys {
                viewModel.enableDecoySelection()
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            if newValue == nil {
                viewModel.loadPhotos()
            }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            // Find the index of the selected photo in the photos array
            if let initialIndex = viewModel.photos.firstIndex(where: { $0.id == photo.id }) {
                EnhancedPhotoDetailView(
                    allPhotos: viewModel.photos,
                    initialIndex: initialIndex,
                    showFaceDetection: showFaceDetection,
                    onDelete: { _ in viewModel.loadPhotos() },
                    onDismiss: viewModel.cleanupMemory
                )
            } else {
                // Fallback if photo not found in array
                PhotoDetailView(
                    photo: photo,
                    showFaceDetection: showFaceDetection,
                    onDelete: { _ in viewModel.loadPhotos() },
                    onDismiss: {
                        photo.clearMemory(keepThumbnail: true)
                        // Trigger garbage collection
                        MemoryManager.shared.checkMemoryUsage()
                    }
                )
            }
        }
        .alert(
            "Delete Photo\(viewModel.selectedPhotoIds.count > 1 ? "s" : "")",
            isPresented: $viewModel.showDeleteConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    print("Delete confirmation button pressed, deleting \(viewModel.selectedPhotoIds.count) photos")
                    viewModel.deleteSelectedPhotos()
                }
            },
            message: {
                Text("Are you sure you want to delete \(viewModel.selectedPhotoIds.count) photo\(viewModel.selectedPhotoIds.count > 1 ? "s" : "")? This action cannot be undone.")
            }
        )
        .alert(
            "Too Many Decoys",
            isPresented: $viewModel.showDecoyLimitWarning,
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text("You can select a maximum of \(maxDecoys) decoy photos. Please deselect some photos before saving.")
            }
        )
        .alert(
            "Save Decoy Selection",
            isPresented: $viewModel.showDecoyConfirmation,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    saveDecoySelections()
                }
            },
            message: {
                Text("Are you sure you want to save these \(viewModel.selectedPhotoIds.count) photos as decoys? These will be shown when the emergency PIN is entered.")
            }
        )
    }

    // MARK: - View Components
    
    // Photo grid subview
    private var photosGridView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(viewModel.photos) { photo in
                    PhotoCell(
                        photo: photo,
                        isSelected: viewModel.selectedPhotoIds.contains(photo.id),
                        isSelecting: viewModel.isSelecting,
                        onTap: {
                            handlePhotoTap(photo)
                        },
                        onDelete: {
                            viewModel.prepareToDeleteSinglePhoto(photo)
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // Import progress overlay
    private var importProgressOverlay: some View {
        VStack {
            ProgressView("Importing photos...", value: viewModel.importProgress, total: 1.0)
                .progressViewStyle(LinearProgressViewStyle())
                .padding()

            Text("\(Int(viewModel.importProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 200)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
                .shadow(radius: 5)
        )
    }

    // MARK: - Action Methods
    
    private func handlePhotoTap(_ photo: SecurePhoto) {
        if viewModel.isSelecting {
            viewModel.togglePhotoSelection(photo, isSelectingDecoys: isSelectingDecoys)
        } else {
            selectedPhoto = photo
        }
    }

    // Save selected photos as decoys
    private func saveDecoySelections() {
        viewModel.saveDecoySelections()
        
        // Reset selection and exit decoy mode
        isSelectingDecoys = false

        // Return to settings
        onDismiss?()
        dismiss()
    }
}
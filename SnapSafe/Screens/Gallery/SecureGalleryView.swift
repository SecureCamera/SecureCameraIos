//
//  SecureGalleryView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import PhotosUI
import SwiftUI
import Logging


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
    @AppStorage("showFaceDetection") private var showFaceDetection = true // Using AppStorage to share with Settings
    @StateObject private var viewModel: SecureGalleryViewModel
    @Environment(\.dismiss) private var dismiss
    
    // Callback for dismissing the gallery
    let onDismiss: (() -> Void)?

    // Initializers
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: SecureGalleryViewModel())
    }

    // Initializer for decoy selection mode
    init(selectingDecoys: Bool, onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        self._viewModel = StateObject(wrappedValue: SecureGalleryViewModel(selectingDecoys: selectingDecoys))
    }


    var body: some View {
        NavigationStack {
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
        }
        .navigationTitle(viewModel.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Back button in the leading position
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if viewModel.isSelectingDecoys {
                        viewModel.exitDecoyMode()
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
                    if viewModel.isSelectingDecoys {
                        // Count label and Save button for decoy selection
                        Text(viewModel.decoyCountText)
                            .font(.caption)
                            .foregroundColor(viewModel.decoyCountTextColor)
                        
                        Button("Save") {
                            viewModel.showDecoyConfirmationAlert()
                        }
                        .foregroundColor(.blue)
                        .disabled(viewModel.isSaveDecoyButtonDisabled)
                    } else if viewModel.isSelecting {
                        // Cancel selection button
                        Button("Cancel") {
                            viewModel.cancelSelecting()
                        }
                        .foregroundColor(.red)
                    } else {
                        Button {
                            viewModel.startSelecting()
                        } label: {
                            Label("Select Photos", systemImage: "ellipsis.circle")
                                .background(.blue)
                        }
                    }
                }
            }
            
            // Bottom toolbar with main action buttons
            ToolbarItemGroup(placement: .bottomBar) {
                if !viewModel.isSelectingDecoys && !viewModel.isSelecting {
                    // Normal mode: Import and Refresh buttons
                    PhotosPicker(selection: $viewModel.pickerItems, matching: .images, photoLibrary: .shared()) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .onChange(of: viewModel.pickerItems) { _, newItems in
                        viewModel.processPickerItems(newItems)
                    }
                    
                    Spacer()
                    
//                    Button(action: viewModel.loadPhotos) {
//                        Label("Refresh", systemImage: "arrow.clockwise")
//                    }
                } else if viewModel.isSelecting && viewModel.hasSelection && !viewModel.isSelectingDecoys {
                    // Selection mode: Delete and Share buttons
                    Button(action: { 
                        Logger.ui.info("Delete button pressed in gallery view, selected photos: \(viewModel.selectedPhotoIds.count)")
                        viewModel.showDeleteAlert()
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
        .onAppear(perform: viewModel.onAppear)
        .onChange(of: viewModel.selectedPhoto) { _, newValue in
            viewModel.onSelectedPhotoChange(newValue)
        }
        .fullScreenCover(item: $viewModel.selectedPhoto) { photoDef in
                // Find the index of the selected photo in the photos array
                if let initialIndex = viewModel.photos.firstIndex(where: { $0.photoName == photoDef.photoName }) {
                    EnhancedPhotoDetailView(
                        allPhotos: viewModel.photos,
                        initialIndex: initialIndex,
                        onDelete: { _ in viewModel.onAppear() },
                        onDismiss: {
                            viewModel.clearMemoryForAllPhotos()
                        }
                    )
                } else {
                    // Fallback if photo not found in array
                    PhotoDetailView(
                        photo: photoDef,
                        onDelete: { _ in viewModel.onAppear() },
                        onDismiss: {
                            viewModel.clearMemoryForPhoto(photoDef)
                        }
                    )
                }
            }
            .alert(
                viewModel.deleteAlertTitle,
                isPresented: $viewModel.showDeleteConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        Logger.ui.info("Delete confirmation button pressed, deleting \(viewModel.selectedPhotoIds.count) photos")
                        viewModel.deleteSelectedPhotos()
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
                        viewModel.saveDecoySelections()
                        onDismiss?()
                        dismiss()
                    }
                },
                message: {
                    Text(viewModel.decoyConfirmationMessage)
                }
            )
        }
        }

    // Photo grid subview
    private var photosGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                ForEach(viewModel.photos) { photo in
                    PhotoCell(
                        photo: photo,
                        isSelected: viewModel.selectedPhotoIds.contains(photo),
                        isSelecting: viewModel.isSelecting,
                        onTap: {
                            viewModel.handlePhotoTap(photo)
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

}

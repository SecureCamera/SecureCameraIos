//
//  PhotoObfuscationView.swift
//  SnapSafe
//
//  Created by Claude on 9/11/25.
//

import SwiftUI

struct PhotoObfuscationView: View {
    @StateObject var viewModel: PhotoObfuscationViewModel
    @EnvironmentObject private var nav: AppNavigationState
    
    init(photoDef: PhotoDef, navigator: AppNavigationState) {
        _viewModel = StateObject(wrappedValue:
            PhotoObfuscationViewModel(
                photoDef: photoDef,
                onSave: { _ in navigator.presentedFullScreenCover = nil },
                onDismiss: { navigator.presentedFullScreenCover = nil }
            )
        )
    }
    
    private func onDismiss() {
        nav.presentedFullScreenCover = nil
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                if viewModel.isImageLoading {
                    ProgressView("Loading image...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundColor(.white)
                } else {
                    imageContent
                }
            }
            .navigationTitle("Photo Obfuscation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancel()
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        viewModel.saveChanges()
                        onDismiss()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .alert("Apply Face Masking", isPresented: $viewModel.showBlurConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(viewModel.maskActionTitle) {
                viewModel.applyFaceMasking()
            }
        } message: {
            Text("Are you sure you want to \(viewModel.maskActionVerb) the selected faces? This action cannot be undone.")
        }
        .actionSheet(isPresented: $viewModel.showMaskOptions) {
            ActionSheet(
                title: Text("Select Masking Mode"),
                message: Text("Choose how you want to obfuscate the selected faces"),
                buttons: [
                    .default(Text("Blur")) {
                        viewModel.selectedMaskMode = .blur
                        viewModel.showBlurConfirmation = true
                    },
                    .default(Text("Pixelate")) {
                        viewModel.selectedMaskMode = .pixelate
                        viewModel.showBlurConfirmation = true
                    },
                    .default(Text("Blackout")) {
                        viewModel.selectedMaskMode = .blackout
                        viewModel.showBlurConfirmation = true
                    },
                    .default(Text("Apply Noise")) {
                        viewModel.selectedMaskMode = .noise
                        viewModel.showBlurConfirmation = true
                    },
                    .cancel()
                ]
            )
        }
    }
    
    private var imageContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Main image display
                Image(uiImage: viewModel.displayedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .background(
                        GeometryReader { imageGeometry in
                            Color.clear
                                .onAppear {
                                    viewModel.imageFrameSize = imageGeometry.size
                                }
                        }
                    )
                
                // Face detection overlay
                if viewModel.isFaceDetectionActive {
                    FaceDetectionOverlay(
                        faces: viewModel.detectedFaces,
                        originalSize: viewModel.currentImage?.size ?? .zero,
                        displaySize: viewModel.imageFrameSize,
                        isAddingBox: false,
                        onTap: viewModel.toggleFaceSelection,
                        onCreateBox: { _ in },
                        onResize: { _, _ in },
                        
                    )
                }
                
                // Processing overlay
                if viewModel.processingFaces {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                    
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Processing faces...")
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                controlsOverlay
            }
        }
    }
    
    private var controlsOverlay: some View {
        VStack(spacing: 16) {
            if viewModel.isFaceDetectionActive {
                // Face detection controls
                HStack(spacing: 20) {
                    Button("Cancel Detection") {
                        withAnimation {
                            viewModel.isFaceDetectionActive = false
                            viewModel.detectedFaces = []
                            viewModel.modifiedImage = nil
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.8))
                    .cornerRadius(8)
                    
                    if viewModel.hasFacesSelected {
                        Button(viewModel.maskButtonLabel) {
                            viewModel.showMaskOptions = true
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                    }
                    
                    Button("Share") {
                        viewModel.sharePhoto()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(8)
                }
            } else {
                // Main controls
                HStack(spacing: 20) {
                    Button("Detect Faces") {
                        viewModel.detectFaces()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.orange.opacity(0.8))
                    .cornerRadius(10)
                    
                    Button("Share") {
                        viewModel.sharePhoto()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
}

// MARK: - Preview

#Preview {
    // Create a mock PhotoDef for preview
    let mockPhotoDef = PhotoDef(
        photoName: "preview_photo.jpg",
        photoFormat: "jpg",
        photoFile: URL(fileURLWithPath: "/tmp/preview.jpg")
    )
    
    PhotoObfuscationView(photoDef: mockPhotoDef, navigator: AppNavigationState())
}

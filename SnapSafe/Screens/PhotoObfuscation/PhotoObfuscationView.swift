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
        .alert("Obscure Faces", isPresented: $viewModel.showObscureConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(viewModel.maskActionTitle) {
                viewModel.applyFaceObscuring()
            }
        } message: {
            Text("Are you sure you want to \(viewModel.maskActionVerb) the selected faces? This action cannot be undone.")
        }
    }
    
    private var imageContent: some View {
        VStack(spacing: 0) {
            // Main image area - centered and stable
            GeometryReader { geometry in
                let availableSize = geometry.size

                ZStack {
                    // Main image display - precisely centered
                    Image(uiImage: viewModel.displayedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: availableSize.width, maxHeight: availableSize.height)
                        .position(x: availableSize.width / 2, y: availableSize.height / 2)
                        .background(
                            GeometryReader { imageGeometry in
                                Color.clear
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            viewModel.imageFrameSize = imageGeometry.size
                                        }
                                    }
                                    .onChange(of: imageGeometry.size) { _, newSize in
                                        DispatchQueue.main.async {
                                            viewModel.imageFrameSize = newSize
                                        }
                                    }
                            }
                        )

                    // Face detection overlay - precisely aligned with centered image
                    if viewModel.isFaceDetectionActive && viewModel.imageFrameSize != .zero {
                        FaceDetectionOverlay(
                            faces: viewModel.detectedFaces,
                            originalSize: viewModel.currentImage?.size ?? .zero,
                            displaySize: viewModel.imageFrameSize,
                            isAddingBox: false,
                            onTap: { id in viewModel.toggleFaceSelection(id: id) },
                            onCreateBox: { pt in viewModel.createBox(at: pt) },
                            onMove: { id, delta in viewModel.moveFace(id: id, by: delta) },
                            onSetPosition: { id, bounds in viewModel.setFacePosition(id: id, to: bounds) },
                            onResize: { id, scale in viewModel.resizeFace(id: id, scale: scale) },
                            onSetSize: { id, bounds in viewModel.setFaceSize(id: id, to: bounds) }
                        )
                        .frame(width: viewModel.imageFrameSize.width, height: viewModel.imageFrameSize.height)
                        .position(x: availableSize.width / 2, y: availableSize.height / 2)
                        .clipped()

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
                        .position(x: availableSize.width / 2, y: availableSize.height / 2)
                    }
                }
            }

            // Bottom toolbar
            ObfuscationControlsView(
                onDetectFaces: {
                    viewModel.detectFaces()
                },
                onShare: {
                    viewModel.sharePhoto()
                },
                onCancelDetection: {
                    withAnimation {
                        viewModel.isFaceDetectionActive = false
                        viewModel.detectedFaces = []
                        viewModel.modifiedImage = nil
                    }
                },
                onMaskFaces: {
                    viewModel.showObscureConfirmation = true
                },
                isFaceDetectionActive: viewModel.isFaceDetectionActive,
                hasFacesSelected: viewModel.hasFacesSelected,
                maskButtonLabel: viewModel.maskButtonLabel,
                isProcessing: viewModel.processingFaces
            )
        }
    }
}

// MARK: - ObfuscationControlsView (Private)

private struct ObfuscationControlsView: View {
    var onDetectFaces: () -> Void
    var onShare: () -> Void
    var onCancelDetection: (() -> Void)?
    var onMaskFaces: (() -> Void)?
    var isFaceDetectionActive: Bool
    var hasFacesSelected: Bool
    var maskButtonLabel: String
    var isProcessing: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Separator line
            Divider()
                .background(Color.gray.opacity(0.3))

            HStack {
                if isFaceDetectionActive {
                    // Cancel detection button
                    Button(action: {
                        onCancelDetection?()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 22))
                                .frame(height: 22)
                            Text("Cancel")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .disabled(isProcessing)
                    .opacity(isProcessing ? 0.6 : 1.0)

                    // Mask faces button (conditional)
                    if hasFacesSelected {
                        Button(action: {
                            onMaskFaces?()
                        }) {
                            VStack(spacing: 4) {
                                if isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(height: 22)
                                } else {
                                    Image(systemName: "face.dashed.fill")
                                        .font(.system(size: 22))
                                        .frame(height: 22)
                                }
                                Text(maskButtonLabel)
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                        }
                        .disabled(isProcessing)
                        .opacity(isProcessing ? 0.6 : 1.0)
                    }

                    // Share button
                    Button(action: onShare) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 22))
                                .frame(height: 22)
                            Text("Share")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .disabled(isProcessing)
                    .opacity(isProcessing ? 0.6 : 1.0)
                } else {
                    // Detect faces button
                    Button(action: onDetectFaces) {
                        VStack(spacing: 4) {
                            Image(systemName: "face.dashed")
                                .font(.system(size: 22))
                                .frame(height: 22)
                            Text("Detect Faces")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .disabled(isProcessing)
                    .opacity(isProcessing ? 0.6 : 1.0)

                    // Share button
                    Button(action: onShare) {
                        VStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 22))
                                .frame(height: 22)
                            Text("Share")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .disabled(isProcessing)
                    .opacity(isProcessing ? 0.6 : 1.0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
        }
        .animation(.easeInOut(duration: 0.2), value: isFaceDetectionActive)
        .animation(.easeInOut(duration: 0.2), value: hasFacesSelected)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
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

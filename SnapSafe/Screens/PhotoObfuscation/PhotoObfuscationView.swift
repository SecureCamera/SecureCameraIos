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
                onSave: { _ in navigator.navigateBack() },
                onDismiss: { navigator.navigateBack() }
            )
        )
    }

    private func onDismiss() {
        nav.navigateBack()
    }
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // The title gets its own full-width row so it isn't truncated
                // between the Cancel and Save buttons in the nav bar.
                Text("Photo Obfuscation")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.black)

                if viewModel.isImageLoading {
                    ProgressView("Loading image...")
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    imageContent
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // We supply our own leading Cancel button, so hide the system back
        // button to avoid showing two back buttons.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    viewModel.cancel()
                    onDismiss()
                }
                .foregroundStyle(.white)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    viewModel.saveChanges()
                    onDismiss()
                }
                .foregroundStyle(.blue)
                .fontWeight(.semibold)
            }
        }
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Obscure Faces", isPresented: $viewModel.showObscureConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(viewModel.maskActionTitle) {
                viewModel.applyFaceObscuring()
            }
        } message: {
            Text("Are you sure you want to \(viewModel.maskActionVerb) the selected faces? This action cannot be undone.")
        }
        .alert("Obscure Areas", isPresented: $viewModel.showManualBoxObscureConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button(viewModel.manualBoxActionTitle) {
                viewModel.applyManualBoxObscuring()
            }
        } message: {
            Text("Are you sure you want to obscure the selected areas? This action cannot be undone.")
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
                    if (viewModel.isFaceDetectionActive || viewModel.isAddingBox || !viewModel.detectedFaces.isEmpty) && viewModel.imageFrameSize != .zero {
                        FaceDetectionOverlay(
                            faces: viewModel.detectedFaces,
                            originalSize: viewModel.currentImage?.size ?? .zero,
                            displaySize: viewModel.imageFrameSize,
                            onTap: { id in viewModel.toggleFaceSelection(id: id) },
                            onSetPosition: { id, bounds in viewModel.setFacePosition(id: id, to: bounds) },
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
                                .foregroundStyle(.white)
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
                onAddBox: {
                    viewModel.startAddingBoxes()
                },
                onCancelDetection: {
                    withAnimation {
                        viewModel.isFaceDetectionActive = false
                        viewModel.detectedFaces = []
                        viewModel.modifiedImage = nil
                        viewModel.isAddingBox = false
                    }
                },
                onCancelAddBox: {
                    viewModel.stopAddingBoxes()
                    viewModel.clearManualBoxes()
                },
                onMaskFaces: {
                    viewModel.showObscureConfirmation = true
                },
                onObscureAreas: {
                    viewModel.showManualBoxObscureConfirmation = true
                },
                isFaceDetectionActive: viewModel.isFaceDetectionActive,
                isAddingBox: viewModel.isAddingBox,
                hasFacesSelected: viewModel.hasFacesSelected,
                hasManualBoxesSelected: viewModel.hasManualBoxesSelected,
                maskButtonLabel: viewModel.maskButtonLabel,
                manualBoxButtonLabel: viewModel.manualBoxButtonLabel,
                isProcessing: viewModel.processingFaces
            )
        }
    }
}

// MARK: - ObfuscationControlsView (Private)

private struct ObfuscationControlsView: View {
    var onDetectFaces: () -> Void
    var onShare: () -> Void
    var onAddBox: () -> Void
    var onCancelDetection: (() -> Void)?
    var onCancelAddBox: (() -> Void)?
    var onMaskFaces: (() -> Void)?
    var onObscureAreas: (() -> Void)?
    var isFaceDetectionActive: Bool
    var isAddingBox: Bool
    var hasFacesSelected: Bool
    var hasManualBoxesSelected: Bool
    var maskButtonLabel: String
    var manualBoxButtonLabel: String
    var isProcessing: Bool

    var body: some View {
        HStack(spacing: 0) {
            if hasManualBoxesSelected && !isAddingBox && !isFaceDetectionActive {
                MediaToolbarButton(icon: "xmark.circle", label: "Cancel", tint: .gray,
                                   action: { onCancelAddBox?() })
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

                obfuscateButton(icon: "square.dashed", label: manualBoxButtonLabel,
                                action: { onObscureAreas?() })

                MediaToolbarButton(icon: "square.and.arrow.up", label: "Share", tint: .blue,
                                   action: onShare)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

            } else if isFaceDetectionActive {
                MediaToolbarButton(icon: "xmark.circle", label: "Cancel", tint: .gray,
                                   action: { onCancelDetection?() })
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

                if hasFacesSelected {
                    obfuscateButton(icon: "face.dashed.fill", label: maskButtonLabel,
                                    action: { onMaskFaces?() })
                }

                MediaToolbarButton(icon: "square.and.arrow.up", label: "Share", tint: .blue,
                                   action: onShare)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

            } else if isAddingBox {
                MediaToolbarButton(icon: "xmark.circle", label: "Cancel", tint: .gray,
                                   action: { onCancelAddBox?() })

                MediaToolbarButton(icon: "plus.app", label: "Add Box", tint: .green,
                                   action: onAddBox)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

                if hasManualBoxesSelected {
                    obfuscateButton(icon: "square.dashed", label: manualBoxButtonLabel,
                                    action: { onObscureAreas?() })
                }

                MediaToolbarButton(icon: "square.and.arrow.up", label: "Share", tint: .blue,
                                   action: onShare)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

            } else {
                MediaToolbarButton(icon: "face.dashed", label: "Detect Faces", tint: .orange,
                                   action: onDetectFaces)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

                MediaToolbarButton(icon: "plus.app", label: "Add Box", tint: .green,
                                   action: onAddBox)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)

                MediaToolbarButton(icon: "square.and.arrow.up", label: "Share", tint: .blue,
                                   action: onShare)
                    .disabled(isProcessing).opacity(isProcessing ? 0.6 : 1.0)
            }
        }
        .glassToolbarBackground()
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .animation(.easeInOut(duration: 0.2), value: isFaceDetectionActive)
        .animation(.easeInOut(duration: 0.2), value: hasFacesSelected)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
    }

    /// Destructive obfuscate button — shows a spinner while processing.
    @ViewBuilder
    private func obfuscateButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        if isProcessing {
            MediaToolbarButton(icon: nil, label: label, tint: .red, action: action) {
                ProgressView().controlSize(.small)
            }
            .disabled(true)
        } else {
            MediaToolbarButton(icon: icon, label: label, tint: .red, action: action)
                .opacity(isProcessing ? 0.6 : 1.0)
        }
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

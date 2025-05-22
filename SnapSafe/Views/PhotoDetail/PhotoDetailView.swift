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

// Use a different name to avoid conflicts with the top-level typealias
struct PhotoDetailView_Impl: View {
    // ViewModel
    @StateObject private var viewModel: PhotoDetailViewModel
    
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // UIKit integration for sharing
    @State private var rootViewController: UIViewController?
    
    // Initialize with a single photo
    init(photo: SecurePhoto, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoDetailViewModel(
            photo: photo,
            showFaceDetection: showFaceDetection,
            onDelete: onDelete,
            onDismiss: onDismiss
        ))
    }
    
    // Initialize with multiple photos
    init(allPhotos: [SecurePhoto], initialIndex: Int, showFaceDetection: Bool, onDelete: ((SecurePhoto) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: PhotoDetailViewModel(
            allPhotos: allPhotos,
            initialIndex: initialIndex,
            showFaceDetection: showFaceDetection,
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
                    if !viewModel.allPhotos.isEmpty {
                        Text("\(viewModel.currentIndex + 1) of \(viewModel.allPhotos.count)")
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
                    
                    // Centered image display
                    ZoomableImageView(
                        image: viewModel.displayedImage,
                        geometrySize: geometry.size,
                        imageFrameSize: $viewModel.imageFrameSize,
                        currentScale: $viewModel.currentScale,
                        lastScale: $viewModel.lastScale,
                        offset: $viewModel.offset,
                        dragOffset: $viewModel.dragOffset,
                        lastDragPosition: $viewModel.lastDragPosition,
                        isZoomed: $viewModel.isZoomed,
                        isSwiping: $viewModel.isSwiping,
                        canGoToPrevious: viewModel.canGoToPrevious,
                        canGoToNext: viewModel.canGoToNext,
                        onNavigatePrevious: viewModel.navigateToPrevious,
                        onNavigateNext: viewModel.navigateToNext,
                        onDismiss: { 
                            viewModel.onDisappear()
                            dismiss() 
                        },
                        onReset: viewModel.resetZoomAndPan,
                        imageRotation: viewModel.imageRotation,
                        isFaceDetectionActive: viewModel.isFaceDetectionActive
                    ) {
                        // Face detection overlay
                        if viewModel.isFaceDetectionActive {
                            FaceDetectionOverlay(
                                faces: viewModel.detectedFaces,
                                originalSize: viewModel.currentPhoto.fullImage.size,
                                displaySize: viewModel.imageFrameSize,
                                isAddingBox: false,
                                onTap: viewModel.toggleFaceSelection,
                                onCreateBox: { _ in }, // Implemented through another method
                                onResize: { face, scale in
                                    // Find and resize the face
                                    if let index = viewModel.detectedFaces.firstIndex(where: { $0.id == face.id }) {
                                        // Create a new face with adjusted bounds
                                        let centerX = face.bounds.midX
                                        let centerY = face.bounds.midY
                                        let newWidth = face.bounds.width * scale
                                        let newHeight = face.bounds.height * scale
                                        let newX = centerX - newWidth / 2
                                        let newY = centerY - newHeight / 2
                                        let newRect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)
                                        
                                        let resizedFace = DetectedFace(
                                            bounds: newRect,
                                            isSelected: face.isSelected,
                                            isUserCreated: face.isUserCreated
                                        )
                                        
                                        var updatedFaces = viewModel.detectedFaces
                                        updatedFaces[index] = resizedFace
                                        viewModel.detectedFaces = updatedFaces
                                    }
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: geometry.size.height * 0.7)
                    .background(UIViewControllerRepresentable())
                    
                    Spacer()
                    
                    // Processing indicator
                    if viewModel.processingFaces {
                        ProgressView("Detecting faces...")
                            .padding()
                    }
                    
                    // Controls - conditionally show face detection controls or standard controls
                    if viewModel.isFaceDetectionActive {
                        FaceDetectionControlsView(
                            onCancel: {
                                withAnimation {
                                    viewModel.isFaceDetectionActive = false
                                    viewModel.detectedFaces = []
                                    viewModel.modifiedImage = nil
                                }
                            },
                            onAddBox: {
                                // Toggle adding box mode
                                // This would be implemented in the viewModel
                            },
                            onMask: {
                                viewModel.showMaskOptions = true
                            },
                            isAddingBox: false,
                            hasFacesSelected: viewModel.hasFacesSelected,
                            faceCount: viewModel.detectedFaces.count,
                            selectedCount: viewModel.detectedFaces.filter({ $0.isSelected }).count
                        )
                    } else {
                        PhotoControlsView(
                            onInfo: { viewModel.showImageInfo = true },
                            onObfuscate: viewModel.detectFaces,
                            onShare: {
                                // Get the rootViewController for sharing
                                if let controller = rootViewController {
                                    viewModel.sharePhoto(from: controller)
                                }
                            },
                            onDelete: { 
                                print("Delete button pressed - showing confirmation")
                                viewModel.showDeleteConfirmation = true 
                            },
                            isZoomed: viewModel.isZoomed
                        )
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
            .alert(
                viewModel.maskActionTitle,
                isPresented: $viewModel.showBlurConfirmation,
                actions: {
                    Button("Cancel", role: .cancel) {}
                    Button(viewModel.maskButtonLabel, role: .destructive) {
                        viewModel.applyFaceMasking()
                    }
                },
                message: {
                    Text("Are you sure you want to \(viewModel.maskActionVerb) the selected faces? This will permanently modify the photo.")
                }
            )
            .sheet(isPresented: $viewModel.showImageInfo) {
                ImageInfoView(photo: viewModel.currentPhoto)
            }
            .actionSheet(isPresented: $viewModel.showMaskOptions) {
                ActionSheet(
                    title: Text("Select Mask Type"),
                    message: Text("Choose how to mask the selected faces"),
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
                        .default(Text("Noise")) {
                            viewModel.selectedMaskMode = .noise
                            viewModel.showBlurConfirmation = true
                        },
                        .cancel()
                    ]
                )
            }
            .onAppear {
                viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
        }
    }
    
    // UIViewControllerRepresentable to get access to the UIViewController for sharing
    struct UIViewControllerRepresentable: UIViewRepresentable {
        func makeUIView(context: Context) -> UIView {
            let view = UIView()
            return view
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            // Store the view controller when available
            if let viewController = findViewController(from: uiView) {
                DispatchQueue.main.async {
                    // Store a reference to the view controller
                    if let photoDetailView = findPhotoDetailView(from: viewController) {
                        photoDetailView.rootViewController = viewController
                    }
                }
            }
        }
        
        // Helper to find the parent view controller from a UIView
        private func findViewController(from view: UIView) -> UIViewController? {
            var responder: UIResponder? = view
            while responder != nil {
                if let viewController = responder as? UIViewController {
                    return viewController
                }
                responder = responder?.next
            }
            return nil
        }
        
        // Helper to find the PhotoDetailView from a view controller
        private func findPhotoDetailView(from viewController: UIViewController) -> PhotoDetailView_Impl? {
            let mirror = Mirror(reflecting: viewController)
            
            // Check if the view controller has a hosting controller
            for child in mirror.children {
                if let content = child.value as? PhotoDetailView_Impl {
                    return content
                }
                
                // Check deeper if there's a hosting view
                if let hosting = child.value as? UIView {
                    let hostingMirror = Mirror(reflecting: hosting)
                    for hostingChild in hostingMirror.children {
                        if let content = hostingChild.value as? PhotoDetailView_Impl {
                            return content
                        }
                    }
                }
            }
            
            return nil
        }
    }
}
//
//  ZoomableImageView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI

// Move the preference key outside the generic view
struct ImageSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct ZoomableImageView<Overlay: View>: View {
    // Image to display
    let image: UIImage
    
    // Geometry and size
    let geometrySize: CGSize
    @Binding var imageFrameSize: CGSize
    
    // Zoom and pan state
    @Binding var currentScale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGFloat
    @Binding var dragOffset: CGSize
    @Binding var lastDragPosition: CGSize
    @Binding var isZoomed: Bool
    @Binding var isSwiping: Bool
    
    // Navigation state
    let canGoToPrevious: Bool
    let canGoToNext: Bool
    var onNavigatePrevious: () -> Void
    var onNavigateNext: () -> Void
    var onDismiss: () -> Void
    var onReset: () -> Void
    let imageRotation: Double
    
    // Face detection state
    let isFaceDetectionActive: Bool
    
    // Orientation properties
    private var isLandscape: Bool {
        // Consider the image orientation
        let orientation = image.imageOrientation.rawValue
        // Orientations 5-8 are 90/270 degree rotations
        let isRotated = orientation >= 5 && orientation <= 8
        
        if isRotated {
            // For rotated images, swap dimensions for comparison
            return image.size.height > image.size.width
        } else {
            // Normal comparison
            return image.size.width > image.size.height
        }
    }
    
    // Device orientation state
    @State private var deviceOrientation = UIDevice.current.orientation
    
    // Custom overlay
    @ViewBuilder var overlay: () -> Overlay
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color that adapts to user theme
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                // Image display that fills the entire screen
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .rotationEffect(.degrees(imageRotation))
                    .scaleEffect(currentScale)
                    .offset(x: offset + dragOffset.width, y: dragOffset.height)
                    .animation(.interactiveSpring(), value: offset) // Smooth animation for offset
                    .animation(nil, value: dragOffset) // No animation for drag to prevent jumping
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height
                    )
                    .clipped() // Clip any overflow from .fill scaling
                        .overlay(
                            GeometryReader { imageGeometry in
                                ZStack {
                                    Color.clear
                                        .preference(key: ImageSizePreferenceKey.self, value: imageGeometry.size)
                                        .onPreferenceChange(ImageSizePreferenceKey.self) { size in
                                            self.imageFrameSize = size
                                        }
                                    
                                    // Custom overlay content
                                    overlay()
                                }
                            }
                        )
                    
                    Spacer()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                // Update device orientation when it changes
                deviceOrientation = UIDevice.current.orientation
            }
            // Apply multiple gestures with a gesture modifier
            .gesture(
                // Magnification (pinch) gesture for zoom in/out
                MagnificationGesture()
                    .onChanged { value in
                        let delta = value / lastScale
                        lastScale = value
                        
                        // Apply zoom with a smoothing factor
                        let newScale = currentScale * delta
                        // Limit the scale to reasonable bounds
                        currentScale = min(max(newScale, 0.5), 6.0)
                        
                        // Update zoomed state for UI adjustments
                        isZoomed = currentScale > 1.1
                    }
                    .onEnded { _ in
                        // Reset lastScale for next gesture
                        lastScale = 1.0
                        
                        // Check if we should return to the gallery
                        if currentScale < 0.6, !isFaceDetectionActive {
                            // User has pinched out enough to dismiss
                            onDismiss()
                        } else if currentScale < 1.0 {
                            // Reset to normal scale
                            onReset()
                        }
                    }
            )
            // Add a drag gesture for panning when zoomed or photo navigation when not zoomed
            .simultaneousGesture(
                DragGesture()
                    .onChanged { gesture in
                        if isZoomed {
                            // When zoomed, add the new translation to the last drag position
                            // This creates a cumulative drag effect
                            self.dragOffset = CGSize(
                                width: lastDragPosition.width + gesture.translation.width,
                                height: lastDragPosition.height + gesture.translation.height
                            )
                        } else if !isFaceDetectionActive {
                            // Handle photo navigation swipe when not zoomed
                            isSwiping = true
                            offset = gesture.translation.width
                        }
                    }
                    .onEnded { _ in
                        if isZoomed {
                            // Calculate the final position including constraints
                            let maxDragDistance = imageFrameSize.width * currentScale / 2
                            let constrainedOffset = CGSize(
                                width: max(-maxDragDistance, min(maxDragDistance, dragOffset.width)),
                                height: max(-maxDragDistance, min(maxDragDistance, dragOffset.height))
                            )
                            
                            // Update dragOffset with the constrained value
                            self.dragOffset = constrainedOffset
                            
                            // Save this position as the new reference point for the next drag
                            self.lastDragPosition = constrainedOffset
                        } else if !isFaceDetectionActive {
                            // When not zoomed, handle photo navigation
                            let threshold: CGFloat = geometrySize.width / 4
                            
                            if offset > threshold, canGoToPrevious {
                                onNavigatePrevious()
                            } else if offset < -threshold, canGoToNext {
                                onNavigateNext()
                            }
                            
                            // Reset the offset with animation
                            withAnimation {
                                offset = 0
                                isSwiping = false
                            }
                        }
                    }
            )
            // Add a double tap gesture to toggle zoom
            .onTapGesture(count: 2) {
                if currentScale > 1.0 {
                    // Reset zoom if zoomed in
                    onReset()
                } else {
                    // Zoom in if not zoomed
                    withAnimation(.spring()) {
                        currentScale = 2.5
                        isZoomed = true
                    }
                }
            }
    }
}

// Preview with sample image
struct ZoomableImageView_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            ZoomableImageView(
                image: UIImage(systemName: "photo")!,
                geometrySize: geometry.size,
                imageFrameSize: .constant(.zero),
                currentScale: .constant(1.0),
                lastScale: .constant(1.0),
                offset: .constant(0),
                dragOffset: .constant(.zero),
                lastDragPosition: .constant(.zero),
                isZoomed: .constant(false),
                isSwiping: .constant(false),
                canGoToPrevious: true,
                canGoToNext: true,
                onNavigatePrevious: {},
                onNavigateNext: {},
                onDismiss: {},
                onReset: {},
                imageRotation: 0,
                isFaceDetectionActive: false
            ) {
                // Sample overlay
                Text("Image Overlay")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
            }
        }
    }
}

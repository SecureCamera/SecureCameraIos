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
    // MARK: – Inputs

    let image: UIImage
    let geometrySize: CGSize
    let canGoToPrevious: Bool
    let canGoToNext: Bool
    let onNavigatePrevious: () -> Void
    let onNavigateNext: () -> Void
    let onDismiss: () -> Void
    let imageRotation: Double
    let isFaceDetectionActive: Bool
    @ViewBuilder var overlay: () -> Overlay

    // MARK: – Zoom / pan state

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset = CGSize.zero // when zoomed
    @State private var accumulatedPan = CGSize.zero // keeps panning between drags

    // MARK: – Temporary drag state (non-zoomed)

    @State private var swipeOffset: CGFloat = 0 // horizontal swipe
    @State private var verticalDrag: CGFloat = 0 // pull-down

    var body: some View {
        GeometryReader { g in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .rotationEffect(.degrees(imageRotation))
                .scaleEffect(scale)
                .offset(x: accumulatedPan.width + panOffset.width + swipeOffset,
                        y: accumulatedPan.height + panOffset.height + verticalDrag)
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
                .overlay(overlay())
                .ignoresSafeArea()
                // ---------- Pinch to zoom ----------
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in
                            let delta = v / lastScale
                            lastScale = v
                            scale = min(max(scale * delta, 0.5), 6)
                        }
                        .onEnded { _ in
                            lastScale = 1
                            if scale < 1 { withAnimation { scale = 1 } }
                        }
                )

                // ---------- Drag (pan, swipe, dismiss) ----------
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1 { // PANNING
                                panOffset = value.translation
                                return
                            }
                            guard !isFaceDetectionActive else { return }

                            let dx = value.translation.width
                            let dy = value.translation.height

                            if abs(dx) > abs(dy) { // HORIZONTAL SWIPE
                                swipeOffset = dx // live follow
                            } else if dy > 0 { // VERTICAL PULL-DOWN
                                verticalDrag = dy * 0.7 // some resistance
                            }
                        }
                        .onEnded { value in
                            if scale > 1 { // finish panning
                                accumulatedPan.width += panOffset.width
                                accumulatedPan.height += panOffset.height
                                panOffset = .zero
                                return
                            }
                            guard !isFaceDetectionActive else { resetNonZoom(); return }

                            let dx = value.translation.width
                            let dy = value.translation.height

                            if abs(dx) > abs(dy) { // ------------ PAGE ------------
                                let threshold = geometrySize.width / 4
                                let quick = abs(value.velocity.width) > 500
                                let quickTh = geometrySize.width / 8

                                if dx > threshold || (quick && dx > quickTh), canGoToPrevious {
                                    onNavigatePrevious()
                                } else if dx < -threshold || (quick && dx < -quickTh), canGoToNext {
                                    onNavigateNext()
                                }
                            } else if dy > 0 { // ----------- DISMISS ----------
                                let threshold = geometrySize.height * 0.25
                                let quick = value.velocity.height > 800
                                if dy > threshold || quick {
                                    onDismiss()
                                }
                            }
                            resetNonZoom()
                        }
                )

                // ---------- Double-tap to toggle zoom ----------
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        scale = scale > 1 ? 1 : 2.5
                    }
                }
        }
    }

    private func resetNonZoom() {
        withAnimation(.spring) {
            swipeOffset = 0
            verticalDrag = 0
        }
    }
}

// struct ZoomableImageView<Overlay: View>: View {
//    // Image to display
//    let image: UIImage
//
//    // Geometry and size
//    let geometrySize: CGSize
//    @Binding var imageFrameSize: CGSize
//
//    // Zoom and pan state
//    @Binding var currentScale: CGFloat
//    @Binding var lastScale: CGFloat
//    @Binding var offset: CGFloat
//    @Binding var dragOffset: CGSize
//    @Binding var lastDragPosition: CGSize
//    @Binding var isZoomed: Bool
//    @Binding var isSwiping: Bool
//
//    // Dismiss gesture state
//    @State private var verticalOffset: CGFloat = 0
//    @State private var dismissProgress: CGFloat = 0
//
//    // Navigation state
//    let canGoToPrevious: Bool
//    let canGoToNext: Bool
//    var onNavigatePrevious: () -> Void
//    var onNavigateNext: () -> Void
//    var onDismiss: () -> Void
//    var onReset: () -> Void
//    let imageRotation: Double
//
//    // Face detection state
//    let isFaceDetectionActive: Bool
//
//    // Orientation properties
//    private var isLandscape: Bool {
//        // Consider the image orientation
//        let orientation = image.imageOrientation.rawValue
//        // Orientations 5-8 are 90/270 degree rotations
//        let isRotated = orientation >= 5 && orientation <= 8
//
//        if isRotated {
//            // For rotated images, swap dimensions for comparison
//            return image.size.height > image.size.width
//        } else {
//            // Normal comparison
//            return image.size.width > image.size.height
//        }
//    }
//
//    // Device orientation state
//    @State private var deviceOrientation = UIDevice.current.orientation
//
//    // Custom overlay
//    @ViewBuilder var overlay: () -> Overlay
//
//    var body: some View {
//        GeometryReader { geometry in
//            ZStack {
//                // Background color that adapts to user theme with dismiss opacity
//                Color(UIColor.systemBackground)
//                    .opacity(1.0 - dismissProgress * 0.7)
//                    .edgesIgnoringSafeArea(.all)
//
//                // Image display that fills the entire screen
//                Image(uiImage: image)
//                    .resizable()
//                    .aspectRatio(contentMode: .fill)
//                    .rotationEffect(.degrees(imageRotation))
//                    .scaleEffect(currentScale * (1.0 - dismissProgress * 0.3)) // Scale down during dismiss
//                    .offset(
//                        x: offset + dragOffset.width,
//                        y: dragOffset.height + verticalOffset
//                    )
//                    .animation(.interactiveSpring(), value: offset) // Smooth animation for offset
//                    .animation(nil, value: dragOffset) // No animation for drag to prevent jumping
//                    .animation(.interactiveSpring(), value: verticalOffset) // Smooth vertical animation
//                    .frame(
//                        width: geometry.size.width,
//                        height: geometry.size.height
//                    )
//                    .clipped() // Clip any overflow from .fill scaling
//                        .overlay(
//                            GeometryReader { imageGeometry in
//                                ZStack {
//                                    Color.clear
//                                        .preference(key: ImageSizePreferenceKey.self, value: imageGeometry.size)
//                                        .onPreferenceChange(ImageSizePreferenceKey.self) { size in
//                                            self.imageFrameSize = size
//                                        }
//
//                                    // Custom overlay content
//                                    overlay()
//                                }
//                            }
//                        )
//
//                    Spacer()
//                }
//            }
//            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
//                // Update device orientation when it changes
//                deviceOrientation = UIDevice.current.orientation
//            }
//            // Apply multiple gestures with a gesture modifier
//            .gesture(
//                // Magnification (pinch) gesture for zoom in/out
//                MagnificationGesture()
//                    .onChanged { value in
//                        let delta = value / lastScale
//                        lastScale = value
//
//                        // Apply zoom with a smoothing factor
//                        let newScale = currentScale * delta
//                        // Limit the scale to reasonable bounds
//                        currentScale = min(max(newScale, 0.5), 6.0)
//
//                        // Update zoomed state for UI adjustments
//                        isZoomed = currentScale > 1.1
//                    }
//                    .onEnded { _ in
//                        // Reset lastScale for next gesture
//                        lastScale = 1.0
//
//                        // Check if we should return to the gallery
//                        if currentScale < 0.6, !isFaceDetectionActive {
//                            // User has pinched out enough to dismiss
//                            onDismiss()
//                        } else if currentScale < 1.0 {
//                            // Reset to normal scale
//                            onReset()
//                        }
//                    }
//            )
//            // Add a drag gesture for panning when zoomed, navigation, or dismiss when not zoomed
//            .simultaneousGesture(
//                DragGesture()
//                    .onChanged { gesture in
//                        if isZoomed {
//                            // When zoomed, add the new translation to the last drag position
//                            // This creates a cumulative drag effect
//                            self.dragOffset = CGSize(
//                                width: lastDragPosition.width + gesture.translation.width,
//                                height: lastDragPosition.height + gesture.translation.height
//                            )
//                        } else if !isFaceDetectionActive {
//                            let horizontalMovement = abs(gesture.translation.width)
//                            let verticalMovement = abs(gesture.translation.height)
//
//                            print("🟡 ZoomableImageView onChanged: H:\(horizontalMovement), V:\(verticalMovement)")
//
//                            if horizontalMovement > verticalMovement {
//                                // Handle horizontal navigation
//                                let threshold: CGFloat = geometrySize.width / 4
//                                let velocity = gesture.velocity.width
//
//                                // Check for swipe velocity (quick swipe with lower threshold)
//                                let isQuickSwipe = abs(velocity) > 500
//                                let quickSwipeThreshold: CGFloat = geometrySize.width / 8
//
//                                if (offset > threshold || (isQuickSwipe && offset > quickSwipeThreshold)) && canGoToPrevious {
//                                    onNavigatePrevious()
//                                } else if (offset < -threshold || (isQuickSwipe && offset < -quickSwipeThreshold)) && canGoToNext {
//                                    onNavigateNext()
//                                }
//
//                                // Reset the offset with animation
//                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
//                                    offset = 0
//                                    isSwiping = false
//                                }
//                            } else if gesture.translation.height > 0 {
//                                // Handle vertical dismiss gesture
//                                let dismissThreshold: CGFloat = geometrySize.height * 0.25
//                                let velocity = gesture.velocity.height
//                                let isQuickDownSwipe = velocity > 800
//
//                                if gesture.translation.height > dismissThreshold || isQuickDownSwipe {
//                                    print("🔴 ZoomableImageView onChanged: DISMISS TRIGGERED!")
//                                    print("   - Translation height: \(gesture.translation.height)")
//                                    print("   - Dismiss threshold: \(dismissThreshold)")
//                                    print("   - Velocity: \(velocity)")
//                                    print("   - Is quick swipe: \(isQuickDownSwipe)")
//                                    // Dismiss the view
//                                    onDismiss()
//                                } else {
//                                    // Snap back to original position
//                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
//                                        verticalOffset = 0
//                                        dismissProgress = 0
//                                    }
//                                }
//                            }
//                        }
//                    }
//                    .onEnded { gesture in
//                        if isZoomed {
//                            // Calculate the final position including constraints
//                            let maxDragDistance = imageFrameSize.width * currentScale / 2
//                            let constrainedOffset = CGSize(
//                                width: max(-maxDragDistance, min(maxDragDistance, dragOffset.width)),
//                                height: max(-maxDragDistance, min(maxDragDistance, dragOffset.height))
//                            )
//
//                            // Update dragOffset with the constrained value
//                            self.dragOffset = constrainedOffset
//
//                            // Save this position as the new reference point for the next drag
//                            self.lastDragPosition = constrainedOffset
//                        } else if !isFaceDetectionActive {
//                            let horizontalMovement = abs(gesture.translation.width)
//                            let verticalMovement = abs(gesture.translation.height)
//
//                            if horizontalMovement > verticalMovement {
//                                // Handle horizontal navigation
//                                let threshold: CGFloat = geometrySize.width / 4
//                                let velocity = gesture.velocity.width
//
//                                // Check for swipe velocity (quick swipe with lower threshold)
//                                let isQuickSwipe = abs(velocity) > 500
//                                let quickSwipeThreshold: CGFloat = geometrySize.width / 8
//
//                                if (offset > threshold || (isQuickSwipe && offset > quickSwipeThreshold)) && canGoToPrevious {
//                                    onNavigatePrevious()
//                                } else if (offset < -threshold || (isQuickSwipe && offset < -quickSwipeThreshold)) && canGoToNext {
//                                    onNavigateNext()
//                                }
//
//                                // Reset the offset with animation
//                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
//                                    offset = 0
//                                    isSwiping = false
//                                }
//                            } else if gesture.translation.height > 0 {
//                                // Handle vertical dismiss gesture
//                                print("🟠 ZoomableImageView: Vertical dismiss gesture in onEnded")
//                                let dismissThreshold: CGFloat = geometrySize.height * 0.25
//                                let velocity = gesture.velocity.height
//                                let isQuickDownSwipe = velocity > 800
//
//                                if gesture.translation.height > dismissThreshold || isQuickDownSwipe {
//                                    print("🔴 ZoomableImageView onEnded: DISMISS TRIGGERED!")
//                                    print("   - Translation height: \(gesture.translation.height)")
//                                    print("   - Dismiss threshold: \(dismissThreshold)")
//                                    print("   - Velocity: \(velocity)")
//                                    print("   - Is quick swipe: \(isQuickDownSwipe)")
//                                    // Dismiss the view
//                                    onDismiss()
//                                } else {
//                                    // Snap back to original position
//                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
//                                        verticalOffset = 0
//                                        dismissProgress = 0
//                                    }
//                                }
//                            }
//                        }
//                    }
//            )
//            // Add a double tap gesture to toggle zoom
//            .onTapGesture(count: 2) {
//                if currentScale > 1.0 {
//                    // Reset zoom if zoomed in
//                    onReset()
//                } else {
//                    // Zoom in if not zoomed
//                    withAnimation(.spring()) {
//                        currentScale = 2.5
//                        isZoomed = true
//                    }
//                }
//            }
//    }
// }

// Preview with sample image
// struct ZoomableImageView_Previews: PreviewProvider {
//    static var previews: some View {
//        GeometryReader { geometry in
//            ZoomableImageView(
//                image: UIImage(systemName: "photo")!,
//                geometrySize: geometry.size,
//                imageFrameSize: .constant(.zero),
//                currentScale: .constant(1.0),
//                lastScale: .constant(1.0),
//                offset: .constant(0),
//                dragOffset: .constant(.zero),
//                lastDragPosition: .constant(.zero),
//                isZoomed: .constant(false),
//                isSwiping: .constant(false),
//                canGoToPrevious: true,
//                canGoToNext: true,
//                onNavigatePrevious: {},
//                onNavigateNext: {},
//                onDismiss: {},
//                onReset: {},
//                imageRotation: 0,
//                isFaceDetectionActive: false
//            ) {
//                // Sample overlay
//                Text("Image Overlay")
//                    .foregroundColor(.white)
//                    .padding(8)
//                    .background(Color.black.opacity(0.7))
//                    .cornerRadius(8)
//            }
//        }
//    }
// }

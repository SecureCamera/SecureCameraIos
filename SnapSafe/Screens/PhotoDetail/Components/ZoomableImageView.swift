//
//  ZoomableImageView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI
import Logging

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
    let canGoToNext:     Bool
    let onNavigatePrevious: () -> Void
    let onNavigateNext:     () -> Void
    let onDismiss:          () -> Void
    let imageRotation:      Double
    let isFaceDetectionActive: Bool
    @ViewBuilder var overlay: () -> Overlay

    // MARK: – Zoom state (communicated to parent)
    @Binding var isZoomed: Bool

    // MARK: – Zoom / pan state
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var panOffset = CGSize.zero        // when zoomed
    @State private var accumulatedPan = CGSize.zero   // keeps panning between drags
    @State private var imageSize: CGSize = .zero      // actual rendered image size

    // MARK: – Temporary drag state (non-zoomed)
    @State private var swipeOffset: CGFloat = 0       // horizontal swipe
    @State private var verticalDrag: CGFloat = 0      // pull-down

    var body: some View {
        GeometryReader { g in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .rotationEffect(.degrees(imageRotation))
                .scaleEffect(scale)
                .offset(x: accumulatedPan.width + panOffset.width + swipeOffset,
                        y: accumulatedPan.height + panOffset.height + verticalDrag)
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
                .overlay(overlay())
                .background(
                    GeometryReader { imageGeometry in
                        Color.clear.preference(
                            key: ImageSizePreferenceKey.self,
                            value: imageGeometry.size
                        )
                    }
                )
                .onPreferenceChange(ImageSizePreferenceKey.self) { size in
                    imageSize = size
                }
                .ignoresSafeArea()

                // ---------- Pinch to zoom ----------
                .gesture(
                    MagnificationGesture()
                        .onChanged { v in
//                            Logger.ui.debug("Pinch onChange: v=\(v), lastScale=\(lastScale), scale=\(scale)")
                            let delta = v / lastScale
                            lastScale = v
                            let newScale = min(max(scale * delta, 0.5), 6)
                            scale = newScale
//                            Logger.ui.debug("  -> newScale=\(newScale)")

                            // DON'T update binding during gesture - wait for onEnded
                        }
                        .onEnded { _ in
//                            Logger.ui.debug("Pinch onEnded: scale=\(scale)")
                            lastScale = 1
                            if scale < 1 {
                                withAnimation {
                                    scale = 1
                                    isZoomed = false
                                }
                            } else {
                                // Update binding after gesture completes
                                isZoomed = scale > 1.0

                                // Reset pan when done zooming
                                accumulatedPan = .zero
                                panOffset = .zero
                            }
                        }
                )

                // ---------- Drag (pan, swipe, dismiss) ----------
                .simultaneousGesture(
                    scale > 1 ?
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Calculate max pan bounds
                            let scaledWidth = imageSize.width * scale
                            let scaledHeight = imageSize.height * scale
                            let maxPanX = max(0, (scaledWidth - geometrySize.width) / 2)
                            let maxPanY = max(0, (scaledHeight - geometrySize.height) / 2)
                            panOffset.width = max(-maxPanX - accumulatedPan.width,
                                                 min(maxPanX - accumulatedPan.width, value.translation.width))
                            panOffset.height = max(-maxPanY - accumulatedPan.height,
                                                  min(maxPanY - accumulatedPan.height, value.translation.height))
                        }
                        .onEnded { value in
                            accumulatedPan.width += panOffset.width
                            accumulatedPan.height += panOffset.height
                            panOffset = .zero
                        }
                    : nil
                )
                .simultaneousGesture(
                    scale <= 1 ?
                    DragGesture()
                        .onChanged { value in
                            guard !isFaceDetectionActive else { return }

                            let dx = value.translation.width
                            let dy = value.translation.height

                            if abs(dx) > abs(dy) {                  // HORIZONTAL SWIPE
                                swipeOffset = dx                    // live follow
                            } else if dy > 0 {                      // VERTICAL PULL-DOWN
                                verticalDrag = dy * 0.7             // some resistance
                            }
                        }
                        .onEnded { value in
                            guard !isFaceDetectionActive else { resetNonZoom() ; return }

                            let dx = value.translation.width
                            let dy = value.translation.height

                            if abs(dx) > abs(dy) {                  // ------------ PAGE ------------
                                let threshold = geometrySize.width / 4
                                let quick = abs(value.velocity.width) > 500
                                let quickTh = geometrySize.width / 8

                                if (dx > threshold || (quick && dx > quickTh)) && canGoToPrevious {
                                    onNavigatePrevious()
                                } else if (dx < -threshold || (quick && dx < -quickTh)) && canGoToNext {
                                    onNavigateNext()
                                }
                            } else if dy > 0 {                      // ----------- DISMISS ----------
                                let threshold = geometrySize.height * 0.25
                                let quick = value.velocity.height > 800
                                if dy > threshold || quick {
                                    onDismiss()
                                }
                            }
                            resetNonZoom()
                        }
                    : nil
                )

                // ---------- Double-tap to toggle zoom ----------
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1 {
                            scale = 1
                            isZoomed = false
                            accumulatedPan = .zero
                            panOffset = .zero
                        } else {
                            scale = 2.5
                            isZoomed = true
                            accumulatedPan = .zero
                            panOffset = .zero
                        }
                    }
                }
        }
    }

    private func resetNonZoom() {
        withAnimation(.spring) {
            swipeOffset   = 0
            verticalDrag  = 0
        }
    }
}

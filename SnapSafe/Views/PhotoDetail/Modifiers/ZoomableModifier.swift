//
//  ZoomableModifier.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI

// View modifier to make a view zoomable and pannable
struct ZoomableModifier: ViewModifier {
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastScale: CGFloat
    @State private var initialScale: CGFloat = 1.0
    var onZoomOut: () -> Void
    var onZoomChange: ((Bool) -> Void)? = nil
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .gesture(makeZoomGesture())
            .gesture(makeDragGesture())
    }
    
    // Create a pinch/zoom gesture
    private func makeZoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Calculate new scale relative to the starting scale
                let delta = value / lastScale
                lastScale = value
                
                let newScale = scale * delta
                // Limit the scale to reasonable bounds
                scale = min(max(newScale, 0.5), 6.0)
                
                // Call callback when zoom state changes
                onZoomChange?(scale > 1.0)
            }
            .onEnded { _ in
                // Reset the lastScale for the next gesture
                lastScale = 1.0
                
                // If user zoomed out below threshold, trigger dismiss
                if scale < 0.6 {
                    onZoomOut()
                } else if scale < 1.0 {
                    // Spring back to normal size if partially zoomed out
                    withAnimation(.spring()) {
                        scale = 1.0
                        offset = .zero
                    }
                }
            }
    }
    
    // Create a drag gesture for panning
    private func makeDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Only enable drag when zoomed in
                if scale > 1.0 {
                    self.offset = CGSize(
                        width: self.offset.width + value.translation.width,
                        height: self.offset.height + value.translation.height
                    )
                }
            }
    }
}

// Extension to make the modifier easier to use
extension View {
    func zoomable(scale: Binding<CGFloat>, offset: Binding<CGSize>, lastScale: Binding<CGFloat>, onZoomOut: @escaping () -> Void, onZoomChange: ((Bool) -> Void)? = nil) -> some View {
        modifier(ZoomableModifier(scale: scale, offset: offset, lastScale: lastScale, onZoomOut: onZoomOut, onZoomChange: onZoomChange))
    }
}
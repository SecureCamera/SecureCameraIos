//
//  FaceDetectionOverlay.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI
import Foundation
import UIKit

struct FaceDetectionOverlay: View {
    let faces: [DetectedFace]
    let originalSize: CGSize
    let displaySize: CGSize
    let isAddingBox: Bool
    var onTap: (DetectedFace) -> Void
    var onCreateBox: (CGPoint) -> Void
    var onResize: (DetectedFace, CGFloat) -> Void
    
    // State for face resizing
    @State private var isResizingBox = false
    @State private var selectedFaceForResize: DetectedFace? = nil
    @State private var currentResizeScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Add a gesture overlay to capture exact tap locations for adding boxes
            if isAddingBox {
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { gesture in
                                onCreateBox(gesture.location)
                            }
                    )
            }
            
            // Overlay each detected face with a rectangle
            ForEach(faces) { face in
                FaceBoxView(
                    face: face,
                    originalSize: originalSize,
                    displaySize: displaySize,
                    onTap: {
                        if !isAddingBox && !isResizingBox {
                            onTap(face)
                        }
                    }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if !isResizingBox {
                                // Start resizing this face
                                isResizingBox = true
                                selectedFaceForResize = face
                                currentResizeScale = 1.0
                            }
                            
                            // Only resize if this is the selected face
                            if let selectedFace = selectedFaceForResize, selectedFace.id == face.id {
                                let delta = value / currentResizeScale
                                currentResizeScale = value
                                onResize(face, delta)
                            }
                        }
                        .onEnded { _ in
                            isResizingBox = false
                            selectedFaceForResize = nil
                            currentResizeScale = 1.0
                        }
                )
            }
        }
    }
}

// Preview with sample faces
struct FaceDetectionOverlay_Previews: PreviewProvider {
    static var previews: some View {
        let faces = [
            DetectedFace(rect: CGRect(x: 50, y: 50, width: 100, height: 100)),
            DetectedFace(rect: CGRect(x: 200, y: 150, width: 120, height: 120), isSelected: true)
        ]
        
        return ZStack {
            Color.gray
            FaceDetectionOverlay(
                faces: faces,
                originalSize: CGSize(width: 400, height: 400),
                displaySize: CGSize(width: 300, height: 300),
                isAddingBox: false,
                onTap: { _ in },
                onCreateBox: { _ in },
                onResize: { _, _ in }
            )
        }
    }
}

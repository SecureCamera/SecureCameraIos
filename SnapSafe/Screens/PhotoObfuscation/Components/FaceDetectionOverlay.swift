//
//  FaceDetectionOverlay.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI
import Foundation
import UIKit

public struct FaceDetectionOverlay: View {
    public let faces: [DetectedFace]
    public let originalSize: CGSize
    public let displaySize: CGSize
    public let isAddingBox: Bool

    public var onTap: (UUID) -> Void
    public var onCreateBox: (CGPoint) -> Void
    public var onMove: (UUID, CGSize) -> Void          // image-space delta
    public var onSetPosition: (UUID, CGRect) -> Void   // absolute position in image space
    public var onResize: (UUID, CGFloat) -> Void       // scale factor
    public var onSetSize: (UUID, CGRect) -> Void       // absolute size for smooth resizing

    @State private var resizingId: UUID?
    @State private var dragStartPositions: [UUID: CGRect] = [:]
    @State private var resizeStartBounds: [UUID: CGRect] = [:]

    public init(
        faces: [DetectedFace],
        originalSize: CGSize,
        displaySize: CGSize,
        isAddingBox: Bool,
        onTap: @escaping (UUID) -> Void,
        onCreateBox: @escaping (CGPoint) -> Void,
        onMove: @escaping (UUID, CGSize) -> Void,
        onSetPosition: @escaping (UUID, CGRect) -> Void,
        onResize: @escaping (UUID, CGFloat) -> Void,
        onSetSize: @escaping (UUID, CGRect) -> Void
    ) {
        self.faces = faces
        self.originalSize = originalSize
        self.displaySize = displaySize
        self.isAddingBox = isAddingBox
        self.onTap = onTap
        self.onCreateBox = onCreateBox
        self.onMove = onMove
        self.onSetPosition = onSetPosition
        self.onResize = onResize
        self.onSetSize = onSetSize
    }

    public var body: some View {
        ZStack {

            ForEach(faces) { face in
                let rect = face.scaledRect(originalSize: originalSize, displaySize: displaySize)

                FaceBoxView(
                    face: face,
                    originalSize: originalSize,
                    displaySize: displaySize,
                    onTap: { onTap(face.id) }
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                // MOVE (one-finger drag)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Store initial position on first drag event
                            if dragStartPositions[face.id] == nil {
                                dragStartPositions[face.id] = face.bounds
                            }

                            guard let startBounds = dragStartPositions[face.id] else { return }

                            // Convert display translation to image space
                            let deltaImage = DetectedFace.imageDelta(
                                fromDisplay: value.translation,
                                originalSize: originalSize,
                                displaySize: displaySize
                            )

                            // Calculate new position from start position
                            let newBounds = CGRect(
                                x: startBounds.origin.x + deltaImage.width,
                                y: startBounds.origin.y + deltaImage.height,
                                width: startBounds.width,
                                height: startBounds.height
                            )

                            onSetPosition(face.id, newBounds)
                        }
                        .onEnded { _ in
                            // Clear stored start position when drag ends
                            dragStartPositions[face.id] = nil
                        }
                )
                // RESIZE (two-finger pinch)
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            // Store initial bounds on first resize event
                            if resizeStartBounds[face.id] == nil {
                                resizeStartBounds[face.id] = face.bounds
                            }

                            guard let startBounds = resizeStartBounds[face.id] else { return }

                            resizingId = face.id

                            // Calculate new size from original size
                            let center = CGPoint(x: startBounds.midX, y: startBounds.midY)
                            let newW = max(12, startBounds.width * scale)
                            let newH = max(12, startBounds.height * scale)

                            let newBounds = CGRect(
                                x: center.x - newW/2,
                                y: center.y - newH/2,
                                width: newW,
                                height: newH
                            )

                            onSetSize(face.id, newBounds)
                        }
                        .onEnded { _ in
                            resizingId = nil
                            // Clear stored start bounds when resize ends
                            resizeStartBounds[face.id] = nil
                        }
                )
            }
        }
    }
}

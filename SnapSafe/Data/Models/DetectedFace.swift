//
//  DetectedFace.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import UIKit

public typealias DetectedFace = _DetectedFace

/// Represents a detected (or user-created) face.
public struct _DetectedFace: Identifiable, Hashable {
    public let id: UUID = UUID()

    public var bounds: CGRect
    public var isSelected: Bool = false
    public var isUserCreated: Bool = false
    public var leftEye: CGPoint?
    public var rightEye: CGPoint?

    public init(bounds: CGRect, isSelected: Bool = false, isUserCreated: Bool = false, leftEye: CGPoint? = nil, rightEye: CGPoint? = nil) {
        self.bounds = bounds.integral
        self.isSelected = isSelected
        self.isUserCreated = isUserCreated
        self.leftEye = leftEye
        self.rightEye = rightEye
    }

    /// Aspect-fit scale and offset for drawing an image of `original` inside a `display` rect.
    /// Returns `(scale, offset)` where `offset` is the top-left inset inside the display area.
    public static func aspectFitScaleAndOffset(original: CGSize, display: CGSize) -> (CGFloat, CGPoint) {
        guard original.width > 0, original.height > 0, display.width > 0, display.height > 0 else {
            return (1, .zero)
        }
        let scale = min(display.width / original.width, display.height / original.height)
        let used = CGSize(width: original.width * scale, height: original.height * scale)
        let offset = CGPoint(x: (display.width - used.width) / 2,
                             y: (display.height - used.height) / 2)
        return (scale, offset)
    }

    /// Convert a display-space delta (drag translation) to image-space delta.
    public static func imageDelta(fromDisplay delta: CGSize, originalSize: CGSize, displaySize: CGSize) -> CGSize {
        let (scale, _) = aspectFitScaleAndOffset(original: originalSize, display: displaySize)
        return CGSize(width: delta.width / scale, height: delta.height / scale)
    }

    /// Rectangle for drawing this face on screen for a centered, aspect-fit image.
    public func scaledRect(originalSize: CGSize, displaySize: CGSize) -> CGRect {
        let (scale, offset) = Self.aspectFitScaleAndOffset(original: originalSize, display: displaySize)
        return CGRect(
            x: bounds.origin.x * scale + offset.x,
            y: bounds.origin.y * scale + offset.y,
            width: bounds.size.width * scale,
            height: bounds.size.height * scale
        )
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DetectedFace, rhs: DetectedFace) -> Bool {
        lhs.id == rhs.id
    }
}

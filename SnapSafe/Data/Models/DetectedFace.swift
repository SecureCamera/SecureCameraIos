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

    public init(rect: CGRect, isSelected: Bool = false) {
        self.init(bounds: rect, isSelected: isSelected, isUserCreated: false)
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

    /// Convert a display-space point (inside the aspect-fit image frame) to image-space.
    public static func imagePoint(fromDisplay p: CGPoint, originalSize: CGSize, displaySize: CGSize) -> CGPoint {
        let (scale, offset) = aspectFitScaleAndOffset(original: originalSize, display: displaySize)
        return CGPoint(x: (p.x - offset.x) / scale, y: (p.y - offset.y) / scale)
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

    /// Return a resized face (center-preserving) by a scale factor in image-space.
    public func resize(by scale: CGFloat, minSize: CGFloat = 12) -> DetectedFace {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let w = max(minSize, bounds.width * scale)
        let h = max(minSize, bounds.height * scale)
        let newRect = CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h).integral
        return DetectedFace(bounds: newRect, isSelected: isSelected, isUserCreated: isUserCreated, leftEye: leftEye, rightEye: rightEye)
    }

    /// Return a new face whose rect is clamped inside the image bounds.
    public func clamped(to imageSize: CGSize) -> DetectedFace {
        var x = max(0, bounds.origin.x)
        var y = max(0, bounds.origin.y)
        var w = bounds.width
        var h = bounds.height

        if x + w > imageSize.width { x = min(x, imageSize.width - 1); w = imageSize.width - x }
        if y + h > imageSize.height { y = min(y, imageSize.height - 1); h = imageSize.height - y }

        let r = CGRect(x: x, y: y, width: max(1, w), height: max(1, h)).integral
        return DetectedFace(bounds: r, isSelected: isSelected, isUserCreated: isUserCreated, leftEye: leftEye, rightEye: rightEye)
    }

    /// Return a translated face by an image-space delta.
    public func moved(by delta: CGSize) -> DetectedFace {
        let r = bounds.offsetBy(dx: delta.width, dy: delta.height).integral
        return DetectedFace(bounds: r, isSelected: isSelected, isUserCreated: isUserCreated, leftEye: leftEye, rightEye: rightEye)
    }

    /// Mutate this face by translating with an image-space delta.
    public mutating func moveInPlace(by delta: CGSize) {
        bounds = bounds.offsetBy(dx: delta.width, dy: delta.height).integral
    }

    /// Mutate this face by resizing around its center by a scale factor.
    public mutating func resizeInPlace(by scale: CGFloat, minSize: CGFloat = 12) {
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let w = max(minSize, bounds.width * scale)
        let h = max(minSize, bounds.height * scale)
        bounds = CGRect(x: c.x - w/2, y: c.y - h/2, width: w, height: h).integral
    }

    /// Clamp this face’s rect inside the image and update in place.
    public mutating func clampInPlace(to imageSize: CGSize) {
        self = clamped(to: imageSize)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DetectedFace, rhs: DetectedFace) -> Bool {
        lhs.id == rhs.id
    }
}

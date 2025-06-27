//
//  DetectedFace.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import UIKit

struct DetectedFace: Identifiable, Codable, Equatable {
    let id = UUID()
    let boundingBox: CGRect
    var isSelected: Bool = false

    // For manually created boxes
    var isUserCreated: Bool = false

    init(boundingBox: CGRect, isSelected: Bool = false, isUserCreated: Bool = false) {
        self.boundingBox = boundingBox
        self.isSelected = isSelected
        self.isUserCreated = isUserCreated
    }

    // Legacy compatibility
    init(bounds: CGRect, isSelected: Bool = false, isUserCreated: Bool = false) {
        self.init(boundingBox: bounds, isSelected: isSelected, isUserCreated: isUserCreated)
    }

    // For compatibility with the original struct
    init(rect: CGRect, isSelected: Bool = false) {
        self.init(boundingBox: rect, isSelected: isSelected)
    }

    var bounds: CGRect {
        boundingBox
    }

    // Calculate scaled rectangle for display in UI
    func scaledRect(originalSize: CGSize, displaySize: CGSize) -> CGRect {
        // Calculate scale factors for width and height
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height

        // Use minimum scale to maintain aspect ratio
        let scale = min(scaleX, scaleY)

        // Calculate the new origin and size for the rectangle
        let scaledWidth = boundingBox.width * scale
        let scaledHeight = boundingBox.height * scale

        // Calculate offsets to center the image within the available space
        let offsetX = (displaySize.width - originalSize.width * scale) / 2
        let offsetY = (displaySize.height - originalSize.height * scale) / 2

        let scaledX = boundingBox.origin.x * scale + offsetX
        let scaledY = boundingBox.origin.y * scale + offsetY

        return CGRect(x: scaledX, y: scaledY, width: scaledWidth, height: scaledHeight)
    }
}

//
//  DetectedFace.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import UIKit

// Define a type alias to this class to avoid conflicts
public typealias DetectedFace = _DetectedFace

// Class to represent a detected face with selection state and resize capability
public class _DetectedFace: Identifiable {
    public let id = UUID()
    let bounds: CGRect
    var isSelected: Bool = false
    
    // For manually created boxes
    var isUserCreated: Bool = false
    
    init(bounds: CGRect, isSelected: Bool = false, isUserCreated: Bool = false) {
        self.bounds = bounds
        self.isSelected = isSelected
        self.isUserCreated = isUserCreated
    }
    
    // For compatibility with the original struct
    convenience init(rect: CGRect, isSelected: Bool = false) {
        self.init(bounds: rect, isSelected: isSelected)
    }
    
    // Calculate scaled rectangle for display in UI
    func scaledRect(originalSize: CGSize, displaySize: CGSize) -> CGRect {
        // Calculate scale factors for width and height
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height
        
        // Use minimum scale to maintain aspect ratio
        let scale = min(scaleX, scaleY)
        
        // Calculate the new origin and size for the rectangle
        let scaledWidth = bounds.width * scale
        let scaledHeight = bounds.height * scale
        
        // Calculate offsets to center the image within the available space
        let offsetX = (displaySize.width - originalSize.width * scale) / 2
        let offsetY = (displaySize.height - originalSize.height * scale) / 2
        
        let scaledX = bounds.origin.x * scale + offsetX
        let scaledY = bounds.origin.y * scale + offsetY
        
        return CGRect(x: scaledX, y: scaledY, width: scaledWidth, height: scaledHeight)
    }
    
    // Function to adjust bounds when the box is resized
    func resize(by scale: CGFloat) -> DetectedFace {
        // Calculate the new center point
        let centerX = bounds.midX
        let centerY = bounds.midY
        
        // Calculate new width and height
        let newWidth = bounds.width * scale
        let newHeight = bounds.height * scale
        
        // Calculate new origin
        let newX = centerX - newWidth / 2
        let newY = centerY - newHeight / 2
        
        // Create new face with updated bounds
        let newFace = DetectedFace(
            bounds: CGRect(x: newX, y: newY, width: newWidth, height: newHeight),
            isSelected: self.isSelected,
            isUserCreated: self.isUserCreated
        )
        
        return newFace
    }
}
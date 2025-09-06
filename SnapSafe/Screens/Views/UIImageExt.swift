//
//  UIImageExt.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//


import SwiftUI

// Extension for UIImage to get an image with the correct orientation applied
extension UIImage {
    func imageWithProperOrientation() -> UIImage {
        // If already in correct orientation, return self
        if self.imageOrientation == .up {
            return self
        }
        
        // Create a proper oriented image
        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(origin: .zero, size: self.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        return normalizedImage
    }
}

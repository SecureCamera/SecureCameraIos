//
//  FaceBoxView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI
import Foundation
import UIKit

struct FaceBoxView: View {
    let face: DetectedFace
    let originalSize: CGSize
    let displaySize: CGSize
    var onTap: () -> Void
    
    // Get the scaled rectangle based on the display size
    private var scaledRect: CGRect {
        let rect = face.scaledRect(originalSize: originalSize, displaySize: displaySize)
        return rect
    }
    
    var body: some View {
        ZStack {
            // Invisible rectangle to make the entire area tappable
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())

            // Draw the rectangle border with color based on selection state
            Rectangle()
                .stroke(face.isSelected ? Color.green : Color.red, lineWidth: 3)

            // Show resize handles for selected faces
            if face.isSelected {
                // Corner handles positioned at the corners of the rectangle
                Circle()
                    .fill(Color.white)
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .position(x: -6, y: -6) // Top-left corner

                Circle()
                    .fill(Color.white)
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .position(x: scaledRect.width + 6, y: -6) // Top-right corner

                Circle()
                    .fill(Color.white)
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .position(x: -6, y: scaledRect.height + 6) // Bottom-left corner

                Circle()
                    .fill(Color.white)
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .position(x: scaledRect.width + 6, y: scaledRect.height + 6) // Bottom-right corner
            }
        }
        .onTapGesture {
            onTap()
        }
    }
}

// Preview with a sample face
struct FaceBoxView_Previews: PreviewProvider {
    static var previews: some View {
        let face = DetectedFace(
            rect: CGRect(x: 50, y: 50, width: 100, height: 100),
            isSelected: true
        )
        
        return ZStack {
            Color.gray
            Image(systemName: "person.fill")
                .resizable()
                .frame(width: 200, height: 200)
            
            FaceBoxView(
                face: face,
                originalSize: CGSize(width: 400, height: 400),
                displaySize: CGSize(width: 300, height: 300),
                onTap: {}
            )
        }
    }
}

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
        face.scaledRect(originalSize: originalSize, displaySize: displaySize)
    }
    
    var body: some View {
        ZStack {
            // Draw the rectangle border with color based on selection state
            Rectangle()
                .stroke(face.isSelected ? Color.green : Color.red, lineWidth: 3)
                .frame(
                    width: scaledRect.width,
                    height: scaledRect.height
                )
            
            // Show resize handles for selected faces
            if face.isSelected {
                Group {
                    // Corner handles
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: scaledRect.minX, y: scaledRect.minY)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: scaledRect.maxX, y: scaledRect.minY)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: scaledRect.minX, y: scaledRect.maxY)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .position(x: scaledRect.maxX, y: scaledRect.maxY)
                }
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 1)
                        .frame(width: 12, height: 12)
                )
            }
        }
        .position(
            x: scaledRect.midX,
            y: scaledRect.midY
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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

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
    var onTap: () -> Void

    var body: some View {
        ZStack {
            // Invisible rectangle to make the entire area tappable
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())

            // Draw the rectangle border with color based on selection state
            Rectangle()
                .stroke(face.isSelected ? Color.green : Color.red, lineWidth: 3)

        }
        .onTapGesture {
            onTap()
        }
    }
}

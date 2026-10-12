//
//  ZoomLevelIndicator.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/20/25.
//

import SwiftUI

struct ZoomLevelIndicator: View {
    let scale: CGFloat
    let isVisible: Bool
    
    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.7))
                .frame(width: 60, height: 25)
            
            Text(String(format: "%.1fx", scale))
                .font(.footnote.bold())
                .foregroundStyle(.white)
        }
        .opacity(isVisible && scale != 1.0 ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: scale)
        .padding(.bottom, 10)
    }
}


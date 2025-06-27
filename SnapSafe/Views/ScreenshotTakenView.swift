//
//  ScreenshotTakenView.swift
//  SnapSafe
//
//  Created by Bill Booth on 6/10/25.
//

import SwiftUI

// View shown when a screenshot is taken
struct ScreenshotTakenView: View {
    var body: some View {
        VStack {
            HStack(spacing: 15) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 24))

                Text("Screenshot Captured")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 10)

            Spacer()
        }
    }
}

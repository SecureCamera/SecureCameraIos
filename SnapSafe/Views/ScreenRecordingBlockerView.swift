//
//  ScreenRecordingBlockerView.swift
//  SnapSafe
//
//  Created by Bill Booth on 6/10/25.
//

import SwiftUI

// View shown when screen recording is detected
struct ScreenRecordingBlockerView: View {
    var body: some View {
        ZStack {
            // Background
            Color.black
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 30) {
                // Warning icon
                Image(systemName: "eye.slash")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .padding(.top, 60)

                // Warning message
                Text("Screen Recording Detected")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                Text("For privacy and security reasons, screen recording is not allowed in SnapSafe.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Text("Please stop recording to continue using SnapSafe.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 20)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    ZStack {
        // Sample content
        VStack {
            Text("Sensitive Content")
                .font(.largeTitle)

            Image(systemName: "person.crop.square")
                .font(.system(size: 100))
        }

        // Preview with screen recording blocker
        ScreenRecordingBlockerView()
    }
}

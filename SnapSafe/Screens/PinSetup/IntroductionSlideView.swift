//
//  IntroductionSlideView.swift
//  SnapSafe
//
//  Created by Claude on 9/14/25.
//

import SwiftUI

struct IntroductionSlideView: View {
    let slide: IntroductionSlide
    
    var body: some View {
        // Just the slide content, no controls
        ScrollView {
            VStack(spacing: 30) {
                // Top spacing
                Spacer()
                    .frame(height: 50)
                
                // Icon
                Image(systemName: slide.icon)
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(slide.iconColor)
                    .padding(.top, 20)
                
                // Title
                Text(slide.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Description
                Text(slide.description)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .padding(.horizontal, 30)
                
                Spacer()
                    .frame(height: 150) // Space for fixed bottom controls
            }
            .padding(.top, 1) // Respect safe area
        }
    }
}
//
//  PINSetupIntroView.swift
//  SnapSafe
//
//  Created by Claude on 9/14/25.
//

import SwiftUI

struct PINSetupIntroView: View {
    @State private var currentSlideIndex = 0
    private let slides = IntroductionSlide.pinSetupSlides
    
    private var isLastIntroSlide: Bool {
        currentSlideIndex == slides.count - 1
    }
    
    private var isOnPINSetupScreen: Bool {
        currentSlideIndex == slides.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            TabView(selection: $currentSlideIndex) {
                // Introduction slides
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    IntroductionSlideView(slide: slide)
                        .tag(index)
                }
                
                // Final slide: PIN creation screen
                PINSetupView()
                    .tag(slides.count)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            // Fixed bottom controls (only show for intro slides, not PIN setup)
            if !isOnPINSetupScreen {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.gray.opacity(0.3))
                    
                    VStack(spacing: 16) {
                        // Progress indicators
                        HStack(spacing: 8) {
                            ForEach(0..<(slides.count + 1), id: \.self) { index in
                                Circle()
                                    .fill(index == currentSlideIndex ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                    .animation(.easeInOut(duration: 0.3), value: currentSlideIndex)
                            }
                        }
                        
                        // Continue button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                currentSlideIndex += 1
                            }
                        }) {
                            HStack {
                                Text(isLastIntroSlide ? "Set Up PIN" : "Continue")
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                }
                .background(Color(UIColor.systemBackground))
            }
        }
        .navigationBarHidden(true)
    }
}

#Preview {
    PINSetupIntroView()
}
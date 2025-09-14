//
//  PoisonPillExplanationView.swift
//  SnapSafe
//
//  Created by Claude on 9/13/25.
//

import SwiftUI

struct PoisonPillExplanationView: View {
    let step: ExplanationStep
    
    init(step: ExplanationStep) {
        self.step = step
    }
    
    var body: some View {
        // Just the scrollable content, no fixed bottom button
        ScrollView {
            VStack(spacing: 30) {
                // Top spacing
                Spacer()
                    .frame(height: 50)
                
                // Header Icon
                Image(systemName: step.icon)
                    .font(.system(size: 80))
                    .foregroundColor(step.iconColor)
                    .padding(.top, 20)
                
                // Title
                Text(step.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Content
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(contentSections, id: \.self) { section in
                        contentSection(section)
                    }
                }
                .padding(.horizontal, 30)
                
                // Bottom spacing for fixed controls
                Spacer()
                    .frame(height: 150)
            }
            .padding(.bottom, 20)
        }
    }
    
    // MARK: - Private Methods
    
    private var contentSections: [String] {
        step.content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    
    @ViewBuilder
    private func contentSection(_ section: String) -> some View {
        let trimmed = section.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.hasPrefix("⚠️") || trimmed.hasPrefix("💡") {
            // Special sections (warnings, tips)
            VStack(spacing: 10) {
                let lines = trimmed.components(separatedBy: "\n")
                if let firstLine = lines.first {
                    Text(firstLine)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                if lines.count > 1 {
                    let remainingText = lines.dropFirst().joined(separator: "\n")
                    Text(remainingText)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColorForSection(trimmed))
            )
        } else {
            // Regular content sections
            VStack(alignment: .leading, spacing: 8) {
                let lines = trimmed.components(separatedBy: "\n")
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedLine.isEmpty {
                        if index == 0 && isSectionHeader(trimmedLine) {
                            // Section header
                            Text(trimmedLine)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(step.iconColor)
                                .padding(.top, index == 0 ? 0 : 15)
                        } else {
                            // Regular content
                            Text(trimmedLine)
                                .font(.body)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .lineSpacing(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func isSectionHeader(_ text: String) -> Bool {
        let headers = ["What is a Poison Pill?", "Ultimate Privacy Protection", 
                      "When to Use", "What Happens", "Making It Less Suspicious", 
                      "The Solution", "How It Works"]
        return headers.contains { text.contains($0) }
    }
    
    private func backgroundColorForSection(_ text: String) -> Color {
        if text.hasPrefix("⚠️") {
            return Color(.systemGray6)
        } else if text.hasPrefix("💡") {
            return Color(.systemYellow).opacity(0.1)
        }
        return Color(.systemGray6)
    }
}

#Preview("Step 1") {
    NavigationView {
        PoisonPillExplanationView(step: ExplanationStep.poisonPillSteps[0])
    }
}

#Preview("Step 2") {
    NavigationView {
        PoisonPillExplanationView(step: ExplanationStep.poisonPillSteps[1])
    }
}

#Preview("Step 3") {
    NavigationView {
        PoisonPillExplanationView(step: ExplanationStep.poisonPillSteps[2])
    }
}

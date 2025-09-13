//
//  PoisonPillExplanationView.swift
//  SnapSafe
//
//  Created by Claude on 9/12/25.
//

import SwiftUI

struct PoisonPillExplanationView: View {
    let onNext: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 30) {
            // Header Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)
                .padding(.top, 40)
            
            // Title
            Text("Emergency Security Feature")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Main Content
            VStack(spacing: 20) {
                explanationCard(
                    icon: "lock.trianglebadge.exclamationmark",
                    title: "What is a Poison Pill?",
                    description: "A special PIN that immediately deletes all your photos and encryption keys when entered, protecting your privacy in emergency situations."
                )
                
                explanationCard(
                    icon: "person.fill.xmark",
                    title: "When to Use",
                    description: "If someone forces you to unlock your phone or you're in a situation where your data security is compromised."
                )
                
                explanationCard(
                    icon: "trash.circle.fill",
                    title: "What Happens",
                    description: "All photos, encryption keys, and sensitive data are permanently deleted. This action cannot be undone."
                )
            }
            .padding(.horizontal, 20)
            
            // Action Buttons
            VStack(spacing: 15) {
                Button(action: onNext) {
                    HStack {
                        Text("Continue Setup")
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(10)
                }
                
                Button("Cancel", action: onCancel)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .navigationBarHidden(true)
    }
    
    @ViewBuilder
    private func explanationCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

#Preview {
    NavigationView {
        PoisonPillExplanationView(
            onNext: {},
            onCancel: {}
        )
    }
}

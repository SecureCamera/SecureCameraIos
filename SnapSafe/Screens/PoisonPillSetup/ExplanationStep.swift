//
//  ExplanationStep.swift
//  SnapSafe
//
//  Created by Claude on 9/13/25.
//

import SwiftUI

struct ExplanationStep {
    let icon: String
    let title: String
    let content: String
    let iconColor: Color
    
    init(icon: String, title: String, content: String, iconColor: Color = .orange) {
        self.icon = icon
        self.title = title
        self.content = content
        self.iconColor = iconColor
    }
}

// MARK: - Poison Pill Explanation Steps

extension ExplanationStep {
    static let poisonPillSteps: [ExplanationStep] = [
        ExplanationStep(
            icon: "exclamationmark.triangle.fill",
            title: "Setup Poison Pill",
            content: """
            What is a Poison Pill?
            
            A Poison Pill is a special emergency PIN that immediately deletes all your photos and encryption keys when entered, protecting your privacy in critical situations.
            """,
            iconColor: .orange
        ),
        
        ExplanationStep(
            icon: "person.fill.xmark",
            title: "When to use it",
            content: """
            This is your last line of defense when you have been coerced to unlock this app. You will lose all of your data, but the attacker will also not get that data.
            
            What Happens
            
            All photos, encryption keys, and sensitive data are permanently deleted.
            
            ⚠️ Warning: This is irreversible
            """,
            iconColor: .orange
        ),
        
        ExplanationStep(
            icon: "photo.badge.plus",
            title: "After Activation",
            content: """
            Once entered, your Poison Pill PIN becomes your real PIN going forward. It is recommended to do a Security Reset of the app once the situation that forced you to use the Pill is over.
            """,
            iconColor: .orange
        )
    ]
}

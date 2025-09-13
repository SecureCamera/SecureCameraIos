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
            title: "Emergency Security Feature",
            content: """
            What is a Poison Pill?
            
            A Poison Pill is a special emergency PIN that immediately deletes all your photos and encryption keys when entered, protecting your privacy in critical situations.
            
            An option of last resort
            
            This is your last line of defense when you have been coerced to unlock this app. You will lose all of your data, but the attack will also not get that data.
            """,
            iconColor: .orange
        ),
        
        ExplanationStep(
            icon: "person.fill.xmark",
            title: "How It Works",
            content: """
            When to Use
            
            Use your Poison Pill PIN if someone forces you to unlock this app against your will.
            
            What Happens
            
            All photos, encryption keys, and sensitive data are permanently deleted. This action cannot be undone.
            
            ⚠️ Warning: This is irreversible
            """,
            iconColor: .orange
        ),
        
        ExplanationStep(
            icon: "photo.badge.plus",
            title: "Decoy Photos Strategy",
            content: """
            Making It Less Suspicious
            
            In the case where you are coerced for your PIN, and you give over your Poison Pill PIN instead, it might be suspicious that there are no photos whatsoever in the Gallery.
            
            The Solution
            
            To solve this it is recommended you take several photos of various innocuous things, and then go into those photos in the Gallery, and mark them as "Decoy" photos.
            
            How It Works
            
            When your Poison Pill is activated, all photos EXCEPT for your Decoys will be deleted, leaving a less suspicious situation.
            
            💡 Pro Tip
            
            Either take photos of every day objects, or: take photos of something that might seem to an attacker to be of a sensetive nature, but that you will not suffer consequences for. This will justify the usage of a secure photo app in their mind.
            """,
            iconColor: .orange
        )
    ]
}

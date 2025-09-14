//
//  IntroductionSlide.swift
//  SnapSafe
//
//  Created by Claude on 9/14/25.
//

import SwiftUI

struct IntroductionSlide {
    let title: String
    let description: String
    let icon: String
    let iconColor: Color = .blue
    
    static let pinSetupSlides: [IntroductionSlide] = [
        IntroductionSlide(
            title: "SnapSafe",
            description: "Welcome to SnapSafe! A free and open source app designed to protect your privacy.\n\nAlong with strong encryption, every measure is taken to safeguard your photos from prying eyes even if your phone is confiscated and searched.",
            icon: "camera.fill"
        ),
        IntroductionSlide(
            title: "Privacy Focused",
            description: "Your PIN is required to take and view the photos, keeping them safe from unauthorized access even if the rest of your device is unlocked.\n\nAfter a few minutes you will be required to enter your PIN again to verify it is still you.",
            icon: "eye.slash.fill"
        ),
        IntroductionSlide(
            title: "Secure Storage",
            description: "Your photos are stored in app-private, encrypted storage. The encryption key is derived from your PIN and is never stored on disk.\n\nNo data, including photos, is ever uploaded or backed up anywhere.",
            icon: "lock"
        ),
        IntroductionSlide(
            title: "Still Shareable",
            description: "Most times we still need to be able to move our sensitive photos out and share them to another app or person. SnapSafe still allows you to do so safely.\n\nOnce the photo leaves SnapSafe, its privacy is up to you.",
            icon: "square.and.arrow.up"
        ),
        IntroductionSlide(
            title: "Meta Data",
            description: "You choose what to do about your photo\'s metadata based on your threat model.\n\nInternally your photos are stored with some basic metadata. Based on your settings, we can automatically strip this data when sharing a photo outside the app.",
            icon: "list.bullet.clipboard"
        ),
        IntroductionSlide(
            title: "Location Data",
            description: "If you grant Location permissions, we\'ll store location in your photos, if you don\'t, we won\'t. It\'s that simple. This metadata will still be stripped out when sharing photos outside the app based on your settings.\n\nIf you only grant \"coarse\" location, then we\'ll store an obfuscated location with each photo.",
            icon: "location.fill"
        ),
    ]
}

//
//  AuthenticationOverlayView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI
import FactoryKit

/// A fullscreen overlay that forces PIN authentication
struct AuthenticationOverlayView: View {
    @InjectedObject(\.appStateCoordinator)
    private var appStateCoordinator: AppStateCoordinator

    var body: some View {
        ZStack {
            // Full screen cover with dark background
            Color.black
                .opacity(0.98)
                .edgesIgnoringSafeArea(.all)
            
            PINVerificationView()
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }
}

/// ViewModifier to add authentication overlay when needed
struct AuthenticationOverlay: ViewModifier {
    @InjectedObject(\.appStateCoordinator)
    private var appStateCoordinator: AppStateCoordinator
 
    func body(content: Content) -> some View {
        ZStack {
            // Main content
            content
            
            // Authentication overlay when needed
            if appStateCoordinator.needsAuthentication {
                AuthenticationOverlayView()
            }
        }
    }
}

// Extension to make the modifier easier to use
extension View {
    /// Add authentication overlay that will appear when authentication is required
    func withAuthenticationOverlay() -> some View {
        modifier(AuthenticationOverlay())
    }
}

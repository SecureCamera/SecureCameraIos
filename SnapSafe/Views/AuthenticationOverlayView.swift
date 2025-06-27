//
//  AuthenticationOverlayView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

// A fullscreen overlay that forces PIN authentication
struct AuthenticationOverlayView: View {
    @ObservedObject private var appStateCoordinator = AppStateCoordinator.shared
    @State private var isAuthenticated = false

    var body: some View {
        ZStack {
            // Full screen cover with dark background
            Color.black
                .opacity(0.98)
                .edgesIgnoringSafeArea(.all)

            // PIN verification view
            PINVerificationView(isAuthenticated: $isAuthenticated)
                .onChange(of: isAuthenticated) { _, authenticated in
                    if authenticated {
                        // Signal that authentication is complete
                        appStateCoordinator.authenticationComplete()
                    }
                }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }
}

// ViewModifier to add authentication overlay when needed
struct AuthenticationOverlay: ViewModifier {
    @ObservedObject private var appStateCoordinator = AppStateCoordinator.shared

    func body(content: Content) -> some View {
        ZStack {
            content

            if appStateCoordinator.needsAuthentication {
                AuthenticationOverlayView()
            }
        }
    }
}

// Extension to make the modifier easier to use
extension View {
    // Add authentication overlay that will appear when authentication is required
    func withAuthenticationOverlay() -> some View {
        modifier(AuthenticationOverlay())
    }
}

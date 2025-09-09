//
//  AuthenticationOverlayView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI
import FactoryKit

/// DEPRECATED: Use SecurityOverlayView with .securityManaged() modifier instead
/// A fullscreen overlay that forces PIN authentication
struct AuthenticationOverlayView: View {
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

/// DEPRECATED: Use SecurityOverlayView with .securityManaged() modifier instead
/// ViewModifier to add authentication overlay when needed
struct AuthenticationOverlay: ViewModifier {
    @InjectedObject(\.securityOverlayViewModel)
    private var securityViewModel: SecurityOverlayViewModel
 
    func body(content: Content) -> some View {
        ZStack {
            // Main content
            content
            
            // Authentication overlay when needed
            if securityViewModel.currentOverlayState == .requiresAuthentication {
                AuthenticationOverlayView()
            }
        }
    }
}

// DEPRECATED: Use .securityManaged() instead
// Extension to make the modifier easier to use
extension View {
    /// Add authentication overlay that will appear when authentication is required
    /// DEPRECATED: Use .securityManaged() modifier instead for unified security management
    func withAuthenticationOverlay() -> some View {
        modifier(AuthenticationOverlay())
    }
}

//
//  PrivacyShield.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

/// Privacy shield to cover content when app is inactive
struct PrivacyShield: View {
    var body: some View {
        ZStack {
            // Background color (dark with opacity)
            Color.black
                .opacity(0.98)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                // App logo/icon
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.white)
                    .padding(.top, 60)
                
                // App name
                Text("SnapSafe")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                
                // Privacy message
                Text("The camera app that minds its own business.")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// ViewModifier to obscure content when app becomes inactive
struct ObscureWhenInactive: ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var obscured = false

    func body(content: Content) -> some View {
        ZStack {
            // Main content that will be obscured when inactive
            content
                .blur(radius: obscured ? 20 : 0)
            
            // Privacy shield overlay
            if obscured {
                PrivacyShield()
                    .transition(.opacity)
            }
        }
        .onChange(of: phase) { _, newPhase in
            // .inactive fires while the task-switcher is animating
            // .background fires a moment later
            print("Scene phase changed to: \(newPhase)")
            obscured = (newPhase != .active)
        }
        // Use quick animation for immediate shield appearance
        .animation(.easeInOut(duration: 0.15), value: obscured)
    }
}

// Extension to make the modifier easier to use
extension View {
    /// Apply privacy shield when app is inactive (task switcher, control center, etc.)
    func obscuredWhenInactive() -> some View {
        modifier(ObscureWhenInactive())
    }
}

#Preview {
    ZStack {
        // Sample background content
        VStack {
            Text("Sensitive Content")
                .font(.largeTitle)
            
            Image(systemName: "person.crop.square")
                .font(.system(size: 100))
        }
        
        // Preview with privacy shield active
        PrivacyShield()
    }
}

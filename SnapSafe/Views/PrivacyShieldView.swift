//
//  PrivacyShieldView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import Combine
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
    @State private var lastStateChange = Date()

    func body(content: Content) -> some View {
        ZStack {
            // Main content that will be obscured when inactive
            content
                .blur(radius: obscured ? 20 : 0)

            // Privacy shield overlay - always present but conditionally opaque
            PrivacyShield()
                .opacity(obscured ? 1.0 : 0.0)
                .allowsHitTesting(obscured)
                .onChange(of: obscured) { _, newValue in
                    print("PrivacyShield opacity changed - obscured: \(newValue), opacity: \(newValue ? 1.0 : 0.0)")
                }
        }
        // Use system notifications as primary trigger - they're more reliable than scene phase
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            print("willResignActiveNotification received - setting obscured to true")
            setObscuredState(true, source: "willResignActive")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            print("didBecomeActiveNotification received - setting obscured to false")
            // Add small delay to prevent flicker when transitioning back to active
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                setObscuredState(false, source: "didBecomeActive")
            }
        }
        // Keep scene phase as backup but with debouncing
        .onChange(of: phase) { _, newPhase in
            print("Scene phase changed to: \(newPhase)")
            let shouldObscure = (newPhase != .active)

            // Only update if enough time has passed since last change (debouncing)
            let timeSinceLastChange = Date().timeIntervalSince(lastStateChange)
            if timeSinceLastChange > 0.2 {
                print("Scene phase backup trigger - setting obscured to: \(shouldObscure)")
                setObscuredState(shouldObscure, source: "scenePhase")
            } else {
                print("Scene phase change ignored due to debouncing (last change \(timeSinceLastChange)s ago)")
            }
        }
    }

    private func setObscuredState(_ newState: Bool, source: String) {
        Task { @MainActor in
            if obscured != newState {
                print("[\(source)] Changing obscured from \(obscured) to \(newState)")
                obscured = newState
                lastStateChange = Date()
                print("[\(source)] Obscured state updated to: \(obscured)")
            } else {
                print("[\(source)] Obscured state already \(newState), no change needed")
            }
        }
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
        VStack {
            Text("Sensitive Content")
                .font(.largeTitle)

            Image(systemName: "person.crop.square")
                .font(.system(size: 100))
        }
        PrivacyShield()
    }
}

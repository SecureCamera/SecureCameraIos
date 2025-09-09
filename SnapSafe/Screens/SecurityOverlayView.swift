//
//  SecurityOverlayView.swift
//  SnapSafe
//
//  Created by Claude on 9/8/25.
//

import SwiftUI
import FactoryKit

// MARK: - Unified Security Overlay

/// A unified overlay that handles all security states (privacy shield, authentication, screen recording)
struct SecurityOverlayView: View {
    let state: SecurityOverlayState
    
    var body: some View {
        ZStack {
            // Background for all overlay states
            Color.black
                .opacity(backgroundOpacity)
                .edgesIgnoringSafeArea(.all)
            
            // Content based on state
            overlayContent
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }
    
    @ViewBuilder
    private var overlayContent: some View {
        switch state {
        case .normal:
            EmptyView()
            
        case .screenRecording:
            ScreenRecordingBlockerContent()
            
        case .requiresAuthentication:
            AuthenticationContent()
            
        case .privacyShield:
            PrivacyShieldContent()
        }
    }
    
    private var backgroundOpacity: Double {
        switch state {
        case .normal: return 0.0
        case .screenRecording: return 1.0
        case .requiresAuthentication: return 0.98
        case .privacyShield: return 0.98
        }
    }
}

// MARK: - Screen Recording Blocker Content

private struct ScreenRecordingBlockerContent: View {
    var body: some View {
        VStack(spacing: 30) {
            // Warning icon
            Image(systemName: "record.circle")
                .font(.system(size: 80))
                .foregroundColor(.red)
                .padding(.top, 60)
            
            // Warning message
            Text("Screen Recording Detected")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text("For privacy and security reasons, screen recording is not allowed in SnapSafe.")
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("Please stop recording to continue using the app.")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.top, 20)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Authentication Content

private struct AuthenticationContent: View {
    var body: some View {
        PINVerificationView()
    }
}

// MARK: - Privacy Shield Content

private struct PrivacyShieldContent: View {
    var body: some View {
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

// MARK: - View Modifier

struct SecurityManagement: ViewModifier {
    @InjectedObject(\.securityOverlayViewModel) 
    private var securityViewModel: SecurityOverlayViewModel
    
    @Environment(\.scenePhase) private var scenePhase
    
    func body(content: Content) -> some View {
        ZStack {
            // Main content
            content
                .blur(radius: shouldBlurContent ? 20 : 0)
            
            // Security overlay
            if securityViewModel.currentOverlayState != .normal {
                SecurityOverlayView(state: securityViewModel.currentOverlayState)
            }
            
            // Screenshot notification (from ScreenCaptureManager)
            if ScreenCaptureManager.shared.screenshotTaken {
                ScreenshotTakenView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            securityViewModel.handleScenePhaseChange(newPhase)
        }
        .onChange(of: securityViewModel.dismissAllSheets) { _, shouldDismiss in
            if shouldDismiss {
                // This will be handled by ContentView to dismiss navigation
                // The view model will reset the flag after a delay
            }
        }
        .animation(.easeInOut(duration: 0.15), value: securityViewModel.currentOverlayState)
        .animation(.easeInOut(duration: 0.3), value: ScreenCaptureManager.shared.screenshotTaken)
    }
    
    private var shouldBlurContent: Bool {
        switch securityViewModel.currentOverlayState {
        case .normal: return false
        case .privacyShield: return true
        case .requiresAuthentication, .screenRecording: return false // These use solid overlays
        }
    }
}

// MARK: - Screenshot Notification View

struct ScreenshotTakenView: View {
    var body: some View {
        VStack {
            HStack(spacing: 15) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 24))
                
                Text("Screenshot Captured")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.top, 10)
            
            Spacer()
        }
    }
}

// MARK: - View Extension

extension View {
    /// Apply unified security management (privacy shield, authentication, screen recording protection)
    func securityManaged() -> some View {
        modifier(SecurityManagement())
    }
}

// MARK: - Previews

#Preview("Privacy Shield") {
    ZStack {
        VStack {
            Text("Sensitive Content")
                .font(.largeTitle)
        }
        
        SecurityOverlayView(state: .privacyShield)
    }
}

#Preview("Screen Recording") {
    ZStack {
        VStack {
            Text("Sensitive Content")
                .font(.largeTitle)
        }
        
        SecurityOverlayView(state: .screenRecording)
    }
}

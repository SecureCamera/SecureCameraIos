//
//  ScreenCaptureManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI
import Combine

/// Manager class to handle screen recording and screenshot detection
class ScreenCaptureManager: ObservableObject {
    // Singleton instance
    static let shared = ScreenCaptureManager()
    
    // Published properties for observers
    @Published var isScreenBeingRecorded = false
    @Published var screenshotTaken = false
    
    // Timer to reset screenshot taken flag
    private var screenshotResetTimer: Timer?
    
    // Private initializer for singleton
    private init() {
        startCaptureMonitoring()
        startScreenshotMonitoring()
    }
    
    /// Start monitoring for screen recording
    func startCaptureMonitoring() {
        // Add observer for screen recording status changes
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleCaptureChange()
        }
        
        // Check initial state
        handleCaptureChange()
    }
    
    /// Handle changes in screen recording status
    private func handleCaptureChange() {
        // Update the published property on the main thread
        DispatchQueue.main.async { [weak self] in
            self?.isScreenBeingRecorded = UIScreen.main.isCaptured
            
            if UIScreen.main.isCaptured {
                print("🔴 Screen recording detected!")
            } else {
                print("✅ Screen recording stopped")
            }
        }
    }
    
    /// Start monitoring for screenshots
    func startScreenshotMonitoring() {
        // Add observer for screenshot notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenshotTaken()
        }
    }
    
    /// Handle screenshot taken event
    private func handleScreenshotTaken() {
        print("📸 Screenshot taken!")
        
        // Reset any existing timer
        screenshotResetTimer?.invalidate()
        
        // Update the flag to trigger UI updates
        DispatchQueue.main.async { [weak self] in
            self?.screenshotTaken = true
            
            // Reset the flag after a delay
            self?.screenshotResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                self?.screenshotTaken = false
            }
        }
        
        // Here you could also log the security event, show a warning, etc.
    }
    
    /// Stop monitoring when the manager is deallocated
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// ViewModifier to apply screen recording protection
struct ScreenRecordingProtection: ViewModifier {
    @ObservedObject private var captureManager = ScreenCaptureManager.shared
    
    func body(content: Content) -> some View {
        ZStack {
            // Original content
            content
                .opacity(captureManager.isScreenBeingRecorded ? 0 : 1)
            
            // Show blocking view if screen is being recorded
            if captureManager.isScreenBeingRecorded {
                ScreenRecordingBlockerView()
                    .transition(.opacity)
            }
            
            // Show screenshot notification if screenshot was taken
            if captureManager.screenshotTaken {
                ScreenshotTakenView()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100) // Make sure it appears on top
            }
        }
        .animation(.easeInOut(duration: 0.2), value: captureManager.isScreenBeingRecorded)
        .animation(.easeInOut(duration: 0.3), value: captureManager.screenshotTaken)
    }
}

// View shown when screen recording is detected
struct ScreenRecordingBlockerView: View {
    var body: some View {
        ZStack {
            // Background
            Color.black
                .edgesIgnoringSafeArea(.all)
            
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
}

// View shown when a screenshot is taken
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

// Extension to make the modifier easier to use
extension View {
    /// Apply protection against screen recording and detect screenshots
    func screenCaptureProtected() -> some View {
        modifier(ScreenRecordingProtection())
    }
}

#Preview {
    ZStack {
        // Sample content
        VStack {
            Text("Sensitive Content")
                .font(.largeTitle)
            
            Image(systemName: "person.crop.square")
                .font(.system(size: 100))
        }
        
        // Preview with screen recording blocker
        ScreenRecordingBlockerView()
    }
}
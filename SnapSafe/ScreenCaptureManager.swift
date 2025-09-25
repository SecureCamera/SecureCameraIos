//
//  ScreenCaptureManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI
import Combine
import Logging


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
        Task { @MainActor [weak self] in
            self?.isScreenBeingRecorded = UIScreen.main.isCaptured
            
            if UIScreen.main.isCaptured {
                Logger.ui.info("🔴 Screen recording detected!")
            } else {
                Logger.ui.info("✅ Screen recording stopped")
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
        Logger.ui.info("📸 Screenshot taken!")
        
        // Reset any existing timer
        screenshotResetTimer?.invalidate()
        
        // Update the flag to trigger UI updates
        Task { @MainActor [weak self] in
            self?.screenshotTaken = true
            
            // Reset the flag after a delay
            self?.screenshotResetTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                self?.screenshotTaken = false
            }
        }
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

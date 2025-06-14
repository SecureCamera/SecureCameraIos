//
//  ContentView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/2/25.
//

import AVFoundation
import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject private var pinManager = PINManager.shared
    @ObservedObject private var appStateCoordinator = AppStateCoordinator.shared
    @State private var isShowingSettings = false
    @State private var isShowingGallery = false
    @State private var isAuthenticated = false
    @State private var isPINSetupComplete = false
    @State private var isShutterAnimating = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared

    // Track device orientation changes
    @State private var deviceOrientation = UIDevice.current.orientation

    var body: some View {
        ZStack {
            if !pinManager.isPINSet {
                // First time setup - show PIN setup screen
                PINSetupView(isPINSetupComplete: $isPINSetupComplete)
            } else if !isAuthenticated || appStateCoordinator.needsAuthentication {
                // PIN verification screen
                PINVerificationView(isAuthenticated: $isAuthenticated)
                    .onChange(of: isAuthenticated) { _, authenticated in
                        if authenticated {
                            // Reset the coordinator's auth state when authenticated
                            appStateCoordinator.authenticationComplete()
                        }
                    }
            } else {
                // Camera view - now contains both the camera preview and focus indicator
                CameraView(cameraModel: cameraModel)
                    .ignoresSafeArea()

                // Shutter animation overlay
                if isShutterAnimating {
                    Color.black
                        .opacity(0.8)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // Camera controls overlay
                VStack {
                    // Top control bar with flash toggle and camera switch
                    HStack {
                        // Camera switch button
                        Button(action: {
                            toggleCameraPosition()
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding(.top, 16)
                        .padding(.leading, 16)

                        Spacer()

                        // Flash control button - disabled for front camera
                        Button(action: {
                            toggleFlashMode()
                        }) {
                            Image(systemName: flashIcon(for: cameraModel.flashMode))
                                .font(.system(size: 20))
                                .foregroundColor(cameraModel.cameraPosition == .front ? .gray : .white)
                                .padding(12)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .disabled(cameraModel.cameraPosition == .front)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                    }

                    Spacer()

                    // Zoom level indicator
                    ZStack {
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 80, height: 30)

                        Text(String(format: "%.1fx", cameraModel.zoomFactor))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    // Show for all zoom levels (including 0.5x for wide angle)
                    .opacity(cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
                    .animation(.easeInOut, value: cameraModel.zoomFactor)
                    .padding(.bottom, 10)
                    // Rotate the zoom indicator based on device orientation
                    .rotationEffect(getRotationAngle())
                    // Separate animation for rotation to ensure it responds to device orientation
                    // changes independent of zoom changes
                    .animation(.easeInOut, value: deviceOrientation)

                    HStack {
                        Button(action: {
                            isShowingGallery = true
                        }) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()

                        Spacer()

                        // Capture button
                        Button(action: {
                            triggerShutterEffect()
                            cameraModel.capturePhoto()
                        }) {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 4)
                                .frame(width: 80, height: 80)
                                .background(Circle().fill(Color.white))
                                .padding()
                        }

                        Spacer()
                        Button(action: {
                            isShowingSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .padding()
                    }
                    .padding(.bottom)
                }
            }
        }
        .animation(.easeInOut(duration: 0.1), value: isShutterAnimating)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .obscuredWhenInactive()
                .screenCaptureProtected()
                .handleAppState(isPresented: $isShowingSettings)
                .withAuthenticationOverlay()
        }
        .fullScreenCover(isPresented: $isShowingGallery) {
            NavigationView {
                SecureGalleryView(onDismiss: {
                    isShowingGallery = false
                })
                .obscuredWhenInactive()
                .screenCaptureProtected()
                .handleAppState(isPresented: $isShowingGallery)
                .withAuthenticationOverlay()
            }
        }
        // Apply privacy shield when app is inactive (task switcher, control center, etc.)
        .obscuredWhenInactive()
        // Protect against screen recording and screenshots
        .screenCaptureProtected()
        // Monitor PIN setup completion
        .onChange(of: isPINSetupComplete) { _, completed in
            if completed {
                print("PIN setup complete, authenticating user")
                isAuthenticated = true
                // Reset flag to avoid issues on subsequent launches
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isPINSetupComplete = false
                }
            }
        }
        .onAppear {
            print("ContentView appeared - PIN is set: \(pinManager.isPINSet), require PIN on resume: \(pinManager.requirePINOnResume)")

            // Check if PIN is set, and only auto-authenticate if PIN check is not required
            if pinManager.isPINSet {
                // Only auto-authenticate if PIN verification is not required
                isAuthenticated = !pinManager.requirePINOnResume
                print("PIN is set, auto-authentication set to: \(isAuthenticated)")
            } else {
                print("PIN is not set, showing PIN setup screen")
            }

            // Start monitoring orientation changes
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                   object: nil,
                                                   queue: .main)
            { _ in
                deviceOrientation = UIDevice.current.orientation
            }
        }
        .onDisappear {
            // Stop monitoring orientation changes
            NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        // Scene phase monitoring for background/foreground transitions
        .onChange(of: scenePhase) { _, newPhase in
            print("ContentView scene phase changed to: \(newPhase)")

            if newPhase == .active {
                // App is becoming active - let coordinator handle this
                appStateCoordinator.handleWillEnterForeground()
            } else if newPhase == .background {
                // App is going to background - let coordinator handle this
                appStateCoordinator.handleDidEnterBackground()
            } else if newPhase == .inactive {
                // Transitional state
                print("App becoming inactive")
            }
        }
        // Monitor authentication state from coordinator
        .onChange(of: appStateCoordinator.needsAuthentication) { _, needsAuth in
            if needsAuth {
                // Force re-authentication
                isAuthenticated = false
            }
        }
        // Monitor dismiss all sheets signal
        .onChange(of: appStateCoordinator.dismissAllSheets) { _, shouldDismiss in
            if shouldDismiss {
                // Dismiss all sheets
                isShowingSettings = false
                isShowingGallery = false

                // Reset flag after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    appStateCoordinator.resetAuthenticationState()
                }
            }
        }
    }

    private func triggerShutterEffect() {
        isShutterAnimating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isShutterAnimating = false
        }
    }

    private func toggleFlashMode() {
        switch cameraModel.flashMode {
        case .auto:
            cameraModel.flashMode = .on
        case .on:
            cameraModel.flashMode = .off
        case .off:
            cameraModel.flashMode = .auto
        @unknown default:
            cameraModel.flashMode = .auto
        }
    }

    // Toggle between front and back cameras
    private func toggleCameraPosition() {
        // Toggle between front and back cameras
        let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
        cameraModel.switchCamera(to: newPosition)
    }

    private func flashIcon(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .auto:
            return "bolt.badge.a"
        case .on:
            return "bolt"
        case .off:
            return "bolt.slash"
        @unknown default:
            return "bolt.badge.a"
        }
    }

    // Get rotation angle for the zoom indicator based on device orientation
    private func getRotationAngle() -> Angle {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            Angle(degrees: 90)
        case .landscapeRight:
            Angle(degrees: -90)
        case .portraitUpsideDown:
            Angle(degrees: 180)
        default:
            Angle(degrees: 0) // Default to portrait
        }
    }
}

// Settings view with sharing, location, and security sections

extension UIDeviceOrientation {
    func getRotationAngle() -> Double {
        switch self {
        case .portrait:
            90 // device upright → rotate 90° CW
        case .portraitUpsideDown:
            270 // device upside down → rotate 270° CW
        case .landscapeLeft:
            0 // device rotated left (home button right) → 0° rotation (natural)
        case .landscapeRight:
            180 // device rotated right (home button left) → 180° rotation
        default:
            90 // Default to portrait rotation if unknown
        }
    }
}

// Extension for UIImage to get an image with the correct orientation applied
extension UIImage {
    func imageWithProperOrientation() -> UIImage {
        // If already in correct orientation, return self
        if imageOrientation == .up {
            return self
        }

        // Create a proper oriented image
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return normalizedImage
    }
}

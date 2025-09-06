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
import FactoryKit


struct ContentView: View { 
    @Injected(\.settingsDataSource) var settings: SettingsDataSource
    
    @StateObject private var cameraModel = CameraModel()
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject private var pinManager = PINManager.shared
    @ObservedObject private var appStateCoordinator = AppStateCoordinator.shared
    @State private var isShowingSettings = false
    @State private var isShowingGallery = false
    @State private var isAuthenticated = false
    @State private var isPINSetupComplete = false
    @State private var isShutterAnimating = false
    @State private var hasCompletedIntro: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var screenCaptureManager = ScreenCaptureManager.shared
    
    // Track device orientation changes
    @State private var deviceOrientation = UIDevice.current.orientation

    var body: some View {
        ZStack {
            if hasCompletedIntro == false {
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
                    .edgesIgnoringSafeArea(.all)

                // Shutter animation overlay
                if isShutterAnimating {
                    Color.black
                        .opacity(0.8)
                        .edgesIgnoringSafeArea(.all)
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
                    .rotationEffect(Utils.getRotationAngle())
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
        .onReceive(settings.hasCompletedIntro) { completed in
            hasCompletedIntro = completed ?? false
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
            print("ContentView appeared - PIN is set: \(hasCompletedIntro), require PIN on resume: \(pinManager.requirePINOnResume)")
            
            // Check if PIN is set, and only auto-authenticate if PIN check is not required
            if hasCompletedIntro {
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
                                                  queue: .main) { _ in
                self.deviceOrientation = UIDevice.current.orientation
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
            Task {
                if newPhase == .active {
                    // App is becoming active - let coordinator handle this
                    await appStateCoordinator.handleWillEnterForeground()
                } else if newPhase == .background {
                    // App is going to background - let coordinator handle this
                    appStateCoordinator.handleDidEnterBackground()
                } else if newPhase == .inactive {
                    // Transitional state
                    print("App becoming inactive")
                }
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
}

// Authentication view for the initial screen
struct AuthenticationView: View {
    @Binding var isAuthenticated: Bool
    @State private var pin = ""
//    private let authManager = AuthenticationManager()

    var body: some View {
        EmptyView()
//        VStack(spacing: 20) {
//            Image(systemName: "lock.shield")
//                .font(.system(size: 70))
//                .foregroundColor(.blue)
//                .padding(.bottom, 30)
//
//            Text("Secure Camera")
//                .font(.largeTitle)
//                .bold()
//
//            Text("Enter your device PIN to continue")
//                .foregroundColor(.secondary)
//
//            // Simulated PIN entry UI
//            // In a real app, we'd use the device authentication
//            SecureField("PIN", text: $pin)
//                .keyboardType(.numberPad)
//                .padding()
//                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
//                .padding(.horizontal, 50)
//
//            Button(action: {
//                // Authenticate with device PIN
//                authManager.authenticate(withMethod: .devicePIN) { success in
//                    if success {
//                        isAuthenticated = true
//                    } else {
//                        // Handle failed authentication
//                        pin = ""
//                    }
//                }
//            }) {
//                Text("Unlock")
//                    .foregroundColor(.white)
//                    .padding()
//                    .frame(width: 200)
//                    .background(Color.blue)
//                    .cornerRadius(10)
//            }
//            .padding(.top, 30)
//        }
//        .padding()
    }
}

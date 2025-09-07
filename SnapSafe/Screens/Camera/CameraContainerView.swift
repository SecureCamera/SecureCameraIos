//
//  CameraContainerView.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import AVFoundation
import SwiftUI

struct CameraContainerView: View {
    @ObservedObject var cameraModel: CameraModel
    @ObservedObject var navigationState: AppNavigationState
    
    // Local camera UI state
    @State private var isShutterAnimating = false
    @State private var deviceOrientation = UIDevice.current.orientation
    
    var body: some View {
        ZStack {
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
                        navigationState.presentFullScreenCover(.gallery)
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
                        navigationState.presentSheet(.settings)
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
        .animation(.easeInOut(duration: 0.1), value: isShutterAnimating)
        .onAppear {
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
    }
    
    // MARK: - Private Methods
    
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

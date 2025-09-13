//
//  CameraContainerView.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import AVFoundation
import SwiftUI
import FactoryKit

struct CameraContainerView: View {
    @StateObject private var viewModel = CameraContainerViewModel()
    @EnvironmentObject private var nav: AppNavigationState
    @InjectedObject(\.cameraPermissionRepository) private var cameraPermissionRepository: CameraPermissionRepository
    
    // Local camera UI state
    @State private var isShutterAnimating = false
    @State private var deviceOrientation = UIDevice.current.orientation
    
    var body: some View {
        ZStack {
            CameraView(cameraModel: viewModel.cameraModel)
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
                        print("Flash button tapped, current mode: \(viewModel.currentFlashMode)")
                        viewModel.toggleFlashMode()
                    }) {
                        Image(systemName: viewModel.flashIcon(for: viewModel.currentFlashMode))
                            .font(.system(size: 20))
                            .foregroundColor(viewModel.cameraModel.cameraPosition == .front ? .gray : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .disabled(viewModel.cameraModel.cameraPosition == .front)
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }

                Spacer()

                // Zoom level indicator
                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 80, height: 30)

                    Text(String(format: "%.1fx", viewModel.cameraModel.zoomFactor))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                // Show for all zoom levels (including 0.5x for wide angle)
                .opacity(viewModel.cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
                .animation(.easeInOut, value: viewModel.cameraModel.zoomFactor)
                .padding(.bottom, 10)
                // Rotate the zoom indicator based on device orientation
                .rotationEffect(Utils.getRotationAngle())
                // Separate animation for rotation to ensure it responds to device orientation
                // changes independent of zoom changes
                .animation(.easeInOut, value: deviceOrientation)

                HStack {
                    Button(action: {
                        nav.presentFullScreenCover(.gallery)
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
                        viewModel.capturePhoto()
                    }) {
                        Circle()
                            .strokeBorder(cameraPermissionRepository.isPermissionGranted ? Color.white : Color.gray, lineWidth: 4)
                            .frame(width: 80, height: 80)
                            .background(Circle().fill(cameraPermissionRepository.isPermissionGranted ? Color.white : Color.gray.opacity(0.5)))
                            .padding()
                    }
                    .disabled(!cameraPermissionRepository.isPermissionGranted)

                    Spacer()
                    Button(action: {
                        nav.presentSheet(.settings)
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
        .onAppear {
            // Re-check camera permissions when view appears
            // This handles the case where user denied permission initially,
            // then granted it in Settings while app was in background
            Task {
                await viewModel.refreshPermissions()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func triggerShutterEffect() {
        isShutterAnimating = true
        Task {
            try await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                isShutterAnimating = false
            }
        }
    }

    // Toggle between front and back cameras
    private func toggleCameraPosition() {
        viewModel.toggleCameraPosition()
    }
}

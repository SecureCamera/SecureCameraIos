//
//  CameraContainerView.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import AVFoundation
import SwiftUI
import FactoryKit
import Logging


struct CameraContainerView: View {
    @StateObject private var cameraModel = CameraViewModel()
    @EnvironmentObject private var nav: AppNavigationState
    
    // Local camera UI state
    @State private var isShutterAnimating = false
    @State private var deviceOrientation = UIDevice.current.orientation
    @State private var showZoomSlider = false
    @State private var isPinching = false
    
    var body: some View {
        ZStack {
            CameraView(cameraModel: cameraModel, onPinchStarted: {
                isPinching = true
                withAnimation {
                    showZoomSlider = true
                }
            }, onPinchChanged: {
                isPinching = true
            }, onPinchEnded: {
                isPinching = false
            })
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
                        Task {
                            let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
                            await cameraModel.switchCamera(to: newPosition)
                        }
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
                        Logger.ui.info("Flash button tapped, current mode: \(cameraModel.flashMode)")
                        cameraModel.toggleFlashMode()
                    }) {
                        Image(systemName: cameraModel.flashIcon)
                            .font(.system(size: 20))
                            .foregroundColor(cameraModel.cameraPosition == .front ? .gray : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .disabled(cameraModel.cameraPosition == .front)
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 16)
                    .padding(.trailing, 16)
                }

                Spacer()

                // Zoom slider (full control)
                if showZoomSlider {
                    ZoomSliderView(cameraModel: cameraModel, isVisible: $showZoomSlider, isPinching: isPinching)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                } else {
                    // Simple zoom level indicator
                    ZStack {
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 80, height: 30)

                        Text(String(format: "%.1fx", cameraModel.zoomFactor))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .opacity(cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
                    .animation(.easeInOut, value: cameraModel.zoomFactor)
                    .padding(.bottom, 10)
                    .rotationEffect(Utils.getRotationAngle())
                    .animation(.easeInOut, value: deviceOrientation)
                    .onTapGesture(count: 2) {
                        handleDoubleTabZoomIndicator()
                    }
                    .onTapGesture {
                        withAnimation {
                            showZoomSlider = true
                        }
                    }
                }

                HStack {
                    Button(action: {
                        nav.presentFullScreenCover(.gallery)
                    }) {
                        ZStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(cameraModel.isSavingPhoto ? .gray : .white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                            if cameraModel.isSavingPhoto {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            }
                        }
                    }
                    .disabled(cameraModel.isSavingPhoto)
                    .padding()

                    Spacer()

                    // Capture button
                    Button(action: {
                        triggerShutterEffect()
                        cameraModel.capturePhoto()
                    }) {
                        ZStack {
                            // Background circle
                            Circle()
                                .strokeBorder(cameraModel.isPermissionGranted ? Color.white : Color.gray, lineWidth: 4)
                                .frame(width: 80, height: 80)
                                .background(
                                    Circle()
                                        .fill(cameraModel.isPermissionGranted ? Color.white : Color.gray.opacity(0.5))
                                )
                            // Overlay shutter icon
                            Image("snapshutter")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 90, height: 90)
                                .foregroundColor(.black)
                        }
                        .padding()
                    }
                    .disabled(!cameraModel.isPermissionGranted)

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
            
            // Initial camera setup - check permissions and configure camera
            Task {
                await cameraModel.checkAndSetupCamera()
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
        Task {
            try await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                isShutterAnimating = false
            }
        }
    }

    private func handleDoubleTabZoomIndicator() {
        Task {
            await cameraModel.zoom(factor: 1.0)
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

}

#Preview {
    // Create a mock camera permission repository with granted permissions for preview
//    @MainActor
//    class MockCameraPermissionRepository: CameraPermissionRepository {
//        override init() {
//            super.init()
//            // Force permission to be granted for preview
//            Task {
//                await self.checkAndUpdatePermissions()
//            }
//        }
//
//        // Override to always return true for preview
//        override var isPermissionGranted: Bool {
//            return true
//        }
//    }

    return CameraContainerView()
        .environmentObject(AppNavigationState())
//        .environmentObject(MockCameraPermissionRepository())
}

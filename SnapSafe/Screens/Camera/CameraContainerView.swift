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
                    // Camera switch button - disabled while recording
                    Button(action: {
                        Task {
                            let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
                            await cameraModel.switchCamera(to: newPosition)
                        }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 20))
                            .foregroundColor(cameraModel.isRecording ? .gray : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .disabled(cameraModel.isRecording)
                    .padding(.top, 16)
                    .padding(.leading, 16)

                    Spacer()

                    // Flash control button - disabled for front camera and while recording
                    Button(action: {
                        Logger.ui.info("Flash button tapped, current mode: \(cameraModel.flashMode)")
                        cameraModel.toggleFlashMode()
                    }) {
                        Image(systemName: cameraModel.flashIcon)
                            .font(.system(size: 20))
                            .foregroundColor((cameraModel.cameraPosition == .front || cameraModel.isRecording) ? .gray : .white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .disabled(cameraModel.cameraPosition == .front || cameraModel.isRecording)
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
                    .gesture(
                        // Use exclusively to properly distinguish single vs double tap
                        TapGesture(count: 2)
                            .onEnded { _ in
                                Logger.camera.debug("Double tap detected on zoom indicator")
                                handleDoubleTabZoomIndicator()
                            }
                            .exclusively(before:
                                TapGesture(count: 1)
                                    .onEnded { _ in
                                        Logger.camera.debug("Single tap detected on zoom indicator")
                                        withAnimation {
                                            showZoomSlider = true
                                        }
                                    }
                            )
                    )
                }

                // Recording duration indicator
                if cameraModel.isRecording {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text(formatDuration(cameraModel.recordingDurationMs))
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                }

                // Mode toggle (Photo / Video)
                Picker("Capture Mode", selection: Binding(
                    get: { cameraModel.captureMode },
                    set: { cameraModel.switchCaptureMode(to: $0) }
                )) {
                    Image(systemName: "camera.fill").tag(CaptureMode.photo)
                    Image(systemName: "video.fill").tag(CaptureMode.video)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .disabled(cameraModel.isRecording)
                .padding(.bottom, 16)

                HStack {
                    Button(action: {
                        nav.navigate(to:.gallery)
                    }) {
                        ZStack {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor((cameraModel.isSavingPhoto || cameraModel.isRecording) ? .gray : .white)
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
                    .disabled(cameraModel.isSavingPhoto || cameraModel.isRecording)
                    .padding()

                    Spacer()

                    // Capture button - conditional based on mode
                    if cameraModel.captureMode == .photo {
                        // Photo capture button
                        Button(action: {
                            triggerShutterEffect()
                            cameraModel.capturePhoto()
                        }) {
                            ZStack {
                                Circle()
                                    .strokeBorder(cameraModel.isPermissionGranted ? Color.white : Color.gray, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                    .background(
                                        Circle()
                                            .fill(cameraModel.isPermissionGranted ? Color.white : Color.gray.opacity(0.5))
                                    )
                                Image("snapshutter")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 90, height: 90)
                                    .foregroundColor(.black)
                            }
                            .padding()
                        }
                        .disabled(!cameraModel.isPermissionGranted)
                    } else {
                        // Video record button
                        Button(action: {
                            cameraModel.toggleRecording()
                        }) {
                            ZStack {
                                Circle()
                                    .strokeBorder(cameraModel.isRecording ? Color.red : Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                                    .background(
                                        Circle()
                                            .fill(cameraModel.isRecording ? Color.red : Color.red.opacity(0.8))
                                    )
                                // Show stop icon when recording, record icon when not
                                if cameraModel.isRecording {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white)
                                        .frame(width: 28, height: 28)
                                } else {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 28, height: 28)
                                }
                            }
                            .padding()
                        }
                        .disabled(!cameraModel.isPermissionGranted)
                    }

                    Spacer()

                    Button(action: {
                        nav.navigate(to:.settings)
                    }) {
                        Image(systemName: "gear")
                            .font(.system(size: 24))
                            .foregroundColor(cameraModel.isRecording ? .gray : .white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .disabled(cameraModel.isRecording)
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
        cameraModel.resetZoomLevel()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
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

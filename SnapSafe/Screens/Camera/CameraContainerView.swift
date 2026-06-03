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

    @State private var isShutterAnimating = false
    @State private var showZoomSlider = false
    @State private var isPinching = false
    @State private var shutterFeedbackTrigger = 0
    @State private var zoomResetTrigger = 0
    @StateObject private var orientation = OrientationObserver()

    var body: some View {
        // The camera UI is locked to portrait. The preview is full-bleed and the
        // controls live in a single column that IGNORES the safe area and pads
        // itself by the STABLE window safe-area insets. This makes the layout
        // immune to the phantom safe-area inset iOS injects when the device is
        // physically rotated while the interface stays locked to portrait — which
        // previously shoved the bottom controls up into the preview. The glyphs
        // still rotate in place (iOS Camera style); capture orientation is
        // handled independently by the capture pipeline.
        ZStack {
            CameraView(cameraModel: cameraModel, onPinchStarted: {
                isPinching = true
                withAnimation { showZoomSlider = true }
            }, onPinchChanged: {
                isPinching = true
            }, onPinchEnded: {
                isPinching = false
            })
            .ignoresSafeArea()

            if isShutterAnimating {
                Color.black
                    .opacity(0.8)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if cameraModel.isEncryptingVideo {
                VStack(spacing: 12) {
                    ProgressView(value: cameraModel.encryptionProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .frame(width: 200)
                    Text("Encrypting video... \(Int(cameraModel.encryptionProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(20)
                .background(Color.black.opacity(0.7))
                .clipShape(.rect(cornerRadius: 12))
            }

            controlsColumn
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.1), value: isShutterAnimating)
        .supportedOrientations(.portrait)
        .onAppear {
            Task {
                await cameraModel.checkAndSetupCamera()
            }
        }
    }

    /// The window's safe-area insets, which stay stable while the interface is
    /// locked to portrait. SwiftUI's environment safe area is unreliable here:
    /// iOS injects a phantom bottom inset on physical rotation even though the
    /// interface never leaves portrait, and that is exactly what we must ignore.
    private var stableSafeInsets: EdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? scenes.first?.keyWindow
        let i = window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        return EdgeInsets(top: i.top, leading: i.left, bottom: i.bottom, trailing: i.right)
    }

    // MARK: - Controls overlay (top bar + zoom + mode picker)

    private var controlsColumn: some View {
        VStack(spacing: 0) {
            // Top controls
            HStack {
                cameraSwitchButton
                Spacer()
                if cameraModel.isRecording {
                    recordingIndicator
                }
                Spacer()
                flashButton
            }

            Spacer(minLength: 0)

            if showZoomSlider {
                ZoomSliderView(cameraModel: cameraModel, isVisible: $showZoomSlider, isPinching: isPinching)
                    .padding(.bottom, 10)
            } else {
                zoomCapsule
                    .frame(height: orientation.orientation.isLandscape ? 96 : 44)
            }

            // Photo / video toggle
            modePicker
                .padding(.bottom, 12)

            // Capture bar (gallery / shutter / settings)
            HStack {
                galleryButton
                Spacer()
                captureButton
                Spacer()
                settingsButton
            }
            .frame(maxWidth: 420)
        }
        .padding(.horizontal, 16)
        .padding(.top, stableSafeInsets.top + 8)
        .padding(.bottom, stableSafeInsets.bottom + 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Individual controls

    private var cameraSwitchButton: some View {
        Button(action: {
            Task {
                let newPosition: AVCaptureDevice.Position = (cameraModel.cameraPosition == .back) ? .front : .back
                await cameraModel.switchCamera(to: newPosition)
            }
        }) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 20))
                .foregroundStyle(cameraModel.isRecording ? .gray : .white)
                .rotatesWithDevice(orientation)
                .padding(12)
                .glassControlBackground(in: Circle())
        }
        .disabled(cameraModel.isRecording)
        .accessibilityLabel(cameraModel.cameraPosition == .back ? "Switch to front camera" : "Switch to rear camera")
    }

    private var flashButton: some View {
        Button(action: {
            Logger.ui.info("Flash button tapped, current mode: \(cameraModel.flashMode)")
            cameraModel.toggleFlashMode()
        }) {
            Image(systemName: cameraModel.flashIcon)
                .font(.system(size: 20))
                .foregroundStyle((cameraModel.cameraPosition == .front || cameraModel.isRecording) ? .gray : .white)
                .rotatesWithDevice(orientation)
                .padding(12)
                .glassControlBackground(in: Circle())
        }
        .disabled(cameraModel.cameraPosition == .front || cameraModel.isRecording)
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Flash: \(cameraModel.flashMode == .on ? "on" : cameraModel.flashMode == .off ? "off" : "auto")")
        .accessibilityHint("Double-tap to cycle flash mode")
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text(formatDuration(cameraModel.recordingDurationMs))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassControlBackground(in: .rect(cornerRadius: 8))
        .accessibilityLabel("Recording: \(formatDuration(cameraModel.recordingDurationMs))")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var zoomCapsule: some View {
        Text(String(format: "%.1fx", cameraModel.zoomFactor))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 80, height: 30)
            .glassControlBackground(in: .capsule)
        .opacity(cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
        .animation(.easeInOut, value: cameraModel.zoomFactor)
        .rotationEffect(Utils.getRotationAngle())
        .gesture(
            TapGesture(count: 2)
                .onEnded { _ in
                    Logger.camera.debug("Double tap detected on zoom indicator")
                    handleDoubleTabZoomIndicator()
                }
                .exclusively(before:
                    TapGesture(count: 1)
                        .onEnded { _ in
                            Logger.camera.debug("Single tap detected on zoom indicator")
                            withAnimation { showZoomSlider = true }
                        }
                )
        )
        .accessibilityLabel(String(format: "Zoom: %.1f×", cameraModel.zoomFactor))
        .accessibilityHint("Double-tap to reset zoom. Single-tap to open slider.")
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(.impact(weight: .medium), trigger: zoomResetTrigger)
    }

    private var modePicker: some View {
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
        .accessibilityLabel("Capture mode")
    }

    private var galleryButton: some View {
        Button(action: { nav.navigate(to: .gallery) }) {
            ZStack {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .foregroundStyle(
                        (cameraModel.isSavingPhoto || cameraModel.isRecording || cameraModel.isEncryptingVideo)
                            ? .gray : .white
                    )
                    .rotatesWithDevice(orientation)
                    .padding()
                    .glassControlBackground(in: Circle())
                if cameraModel.isSavingPhoto {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.7)
                }
            }
        }
        .disabled(cameraModel.isSavingPhoto || cameraModel.isRecording || cameraModel.isEncryptingVideo)
        .padding()
        .accessibilityLabel("Gallery")
        .accessibilityHint(cameraModel.isSavingPhoto ? "Saving photo" : "")
    }

    private var settingsButton: some View {
        Button(action: { nav.navigate(to: .settings) }) {
            Image(systemName: "gear")
                .font(.title2)
                .foregroundStyle((cameraModel.isRecording || cameraModel.isEncryptingVideo) ? .gray : .white)
                .rotatesWithDevice(orientation)
                .padding()
                .glassControlBackground(in: Circle())
        }
        .disabled(cameraModel.isRecording || cameraModel.isEncryptingVideo)
        .padding()
        .accessibilityLabel("Settings")
        #if DEBUG
        .onLongPressGesture(minimumDuration: 2.0) {
            if #available(iOS 18.0, *) {
                nav.navigate(to: .videoExportTest)
            }
        }
        #endif
    }

    private var captureButton: some View {
        Group {
            if cameraModel.captureMode == .photo {
                photoShutterButton
            } else {
                videoRecordButton
            }
        }
    }

    private var photoShutterButton: some View {
        Button(action: {
            shutterFeedbackTrigger += 1
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
                    .foregroundStyle(.black)
            }
            .padding()
        }
        .disabled(!cameraModel.isPermissionGranted)
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterFeedbackTrigger)
        .accessibilityLabel("Take photo")
        .accessibilityHint(cameraModel.isPermissionGranted ? "" : "Camera access required")
    }

    private var videoRecordButton: some View {
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
            .frame(width: 90, height: 90)
            .padding()
        }
        .disabled(!cameraModel.isPermissionGranted)
        .sensoryFeedback(.impact(weight: .heavy), trigger: cameraModel.isRecording) { old, new in
            old == false && new == true
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: cameraModel.isRecording) { old, new in
            old == true && new == false
        }
        .accessibilityLabel(cameraModel.isRecording ? "Stop recording" : "Start recording")
        .accessibilityHint(cameraModel.isPermissionGranted ? "" : "Camera access required")
    }

    // MARK: - Helpers

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
        zoomResetTrigger += 1
    }

    private func formatDuration(_ milliseconds: Int64) -> String {
        let totalSeconds = Int(milliseconds / 1000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    CameraContainerView()
        .environmentObject(AppNavigationState())
}

// MARK: - Liquid Glass control background

private extension View {
    /// Applies a translucent, contrasting control background per the Apple HIG:
    /// Liquid Glass on iOS 26+, with an `.ultraThinMaterial` fallback on earlier
    /// versions (the deployment floor is iOS 18.5).
    ///
    /// The glass is intentionally NOT `.interactive()`: these backgrounds live
    /// inside `Button`s (and tap gestures), and interactive glass installs its
    /// own touch handling that swallows the button's tap. The enclosing control
    /// provides the interaction; this modifier is purely the visual background.
    @ViewBuilder
    func glassControlBackground(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Rotates a control's glyph to stay upright relative to the ground while
    /// the camera UI itself stays locked to portrait (iOS Camera style).
    /// `rotationEffect` does not affect layout, so the control never moves.
    func rotatesWithDevice(_ observer: OrientationObserver) -> some View {
        self
            .rotationEffect(Utils.getRotationAngle(for: observer.orientation))
            .animation(.easeInOut(duration: 0.25), value: observer.orientation)
    }
}

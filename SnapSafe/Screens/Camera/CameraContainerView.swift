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
    @State private var isLandscape = false

    var body: some View {
        ZStack {
            CameraView(cameraModel: cameraModel, onPinchStarted: {
                isPinching = true
                withAnimation { showZoomSlider = true }
            }, onPinchChanged: {
                isPinching = true
            }, onPinchEnded: {
                isPinching = false
            })
            .edgesIgnoringSafeArea(.all)

            if isShutterAnimating {
                Color.black
                    .opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
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

            controlsOverlay
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isLandscape { portraitBar }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if isLandscape { landscapeBar }
        }
        .animation(.easeInOut(duration: 0.1), value: isShutterAnimating)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { isLandscape = geo.size.width > geo.size.height }
                    .onChange(of: geo.size.width > geo.size.height) { _, landscape in
                        isLandscape = landscape
                    }
            }
        )
        .onAppear {
            Task {
                await cameraModel.checkAndSetupCamera()
            }
        }
    }

    // MARK: - Controls overlay (top bar + zoom + mode picker)

    private var controlsOverlay: some View {
        VStack {
            HStack {
                cameraSwitchButton
                    .padding(.top, 16)
                    .padding(.leading, 16)

                Spacer()

                if cameraModel.isRecording {
                    recordingIndicator
                        .padding(.top, 16)
                }

                Spacer()

                flashButton
                    .padding(.top, 16)
                    .padding(.trailing, 16)
            }

            Spacer()

            if showZoomSlider {
                ZoomSliderView(cameraModel: cameraModel, isVisible: $showZoomSlider, isPinching: isPinching)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            } else {
                zoomCapsule
            }

            // Mode picker only in portrait — in landscape it lives in the sidebar
            if !isLandscape {
                modePicker
                    .padding(.bottom, 16)
            }
        }
    }

    // MARK: - Capture bars

    private var portraitBar: some View {
        HStack {
            galleryButton
            Spacer()
            captureButton
            Spacer()
            settingsButton
        }
        .padding(.bottom, 8)
        .background(Color.clear)
    }

    private var landscapeBar: some View {
        VStack {
            galleryButton
            Spacer()
            modePicker
                .padding(.vertical, 4)
            captureButton
            Spacer()
            settingsButton
        }
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.clear)
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
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
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
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
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
        .background(Color.black.opacity(0.6))
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityLabel("Recording: \(formatDuration(cameraModel.recordingDurationMs))")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var zoomCapsule: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.6))
                .frame(width: 80, height: 30)
            Text(String(format: "%.1fx", cameraModel.zoomFactor))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .opacity(cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
        .animation(.easeInOut, value: cameraModel.zoomFactor)
        .padding(.bottom, 10)
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
                .padding()
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
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
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
        .accessibilityLabel("Take photo")
        .accessibilityHint(cameraModel.isPermissionGranted ? "" : "Camera access required")
    }

    private var videoRecordButton: some View {
        Button(action: {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = cameraModel.isRecording ? .medium : .heavy
            UIImpactFeedbackGenerator(style: style).impactOccurred()
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
    CameraContainerView()
        .environmentObject(AppNavigationState())
}

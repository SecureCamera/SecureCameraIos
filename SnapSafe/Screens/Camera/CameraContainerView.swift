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
    @State private var focusExclusionRects: [CGRect] = []
    @StateObject private var orientation = OrientationObserver()

    /// Shared coordinate space spanning the full-screen preview, used to report
    /// overlaid-control frames to the focus gesture as exclusion zones.
    private static let cameraSpaceName = "cameraFocusSpace"

    var body: some View {
        // The camera UI is locked to portrait. The preview is full-bleed and the
        // controls live in a single column that IGNORES the safe area and pads
        // itself by the STABLE window safe-area insets. This makes the layout
        // immune to the phantom safe-area inset iOS injects when the device is
        // physically rotated while the interface stays locked to portrait — which
        // previously shoved the bottom controls up into the preview. The glyphs
        // still rotate in place (iOS Camera style); capture orientation is
        // handled independently by the capture pipeline.
        GeometryReader { proxy in
        ZStack {
            CameraView(cameraModel: cameraModel, focusExclusionRects: focusExclusionRects, onPinchStarted: {
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

            // Saving HUD: stays up for a minimum duration (see the view
            // model's videoSavingGate) and fades in/out, so a short clip's
            // near-instant encryption reads as a confirmation, not a flash.
            if cameraModel.isSavingVideo {
                VStack(spacing: 12) {
                    ProgressView(value: min(cameraModel.encryptionProgress, 1.0), total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .frame(width: 200)
                    Text("Encrypting & saving…")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                .padding(20)
                .background(Color.black.opacity(0.7))
                .clipShape(.rect(cornerRadius: 12))
                // Rotate in place with the device, like the other camera
                // chrome — the interface stays locked to portrait.
                .rotatesWithDevice(orientation)
                .transition(.opacity)
            }

            if cameraModel.isRecording {
                recordingIndicatorOverlay
            }

            controlsColumn(letterbox: letterboxHeight(in: proxy.size))
                .environment(\.colorScheme, .dark)
        }
        .coordinateSpace(.named(Self.cameraSpaceName))
        .onPreferenceChange(FocusExclusionPreferenceKey.self) { rects in
            focusExclusionRects = rects
        }
        .animation(.easeInOut(duration: 0.1), value: isShutterAnimating)
        .animation(.easeInOut(duration: 0.25), value: cameraModel.isSavingVideo)
        .animation(.easeInOut(duration: 0.25), value: cameraModel.isRecording)
        }
        .ignoresSafeArea()
        .supportedOrientations(.portrait)
        .onAppear {
            Task {
                await cameraModel.checkAndSetupCamera()
            }
        }
    }

    /// Height of the black band above/below the preview container in a
    /// full-screen layout of `size`. The control rows pad themselves by this
    /// so they sit just inside the image instead of straddling its edges.
    private func letterboxHeight(in size: CGSize) -> CGFloat {
        let container = CameraPreviewLayout.containerSize(
            for: size,
            aspectRatio: cameraModel.captureAspectRatio
        )
        return max(0, (size.height - container.height) / 2)
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

    /// A transparent reporter to drop in a control's `.background`. It measures
    /// the control's frame in the shared camera coordinate space (optionally
    /// expanded by `expand` for a more liberal margin) and publishes it as a
    /// focus-exclusion zone, so tap-to-focus won't fire on that control.
    private func focusExclusionReporter(expand: CGFloat = 0, active: Bool = true) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: FocusExclusionPreferenceKey.self,
                    value: active
                        ? [proxy.frame(in: .named(Self.cameraSpaceName)).insetBy(dx: -expand, dy: -expand)]
                        : []
                )
        }
    }

    // MARK: - Controls overlay (top bar + zoom + mode picker)

    private func controlsColumn(letterbox: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Top controls
            HStack {
                cameraSwitchButton
                Spacer()
                flashButton
            }
            // Carve this control bar out of the tap-to-focus area so the focus
            // gesture on the preview beneath doesn't swallow the buttons' taps
            // (the capture-area container can span the full width on large
            // screens, putting these controls inside it).
            .background(focusExclusionReporter(expand: 8, active: !cameraModel.isRecording))
            .hideWhileRecording(cameraModel.isRecording)

            Spacer(minLength: 0)

            if showZoomSlider {
                ZoomSliderView(cameraModel: cameraModel, isVisible: $showZoomSlider, isPinching: isPinching)
                    .padding(.bottom, 10)
                    .hideWhileRecording(cameraModel.isRecording)
            } else {
                zoomCapsule
                    .frame(height: orientation.orientation.isLandscape ? 96 : 44)
                    .hideWhileRecording(cameraModel.isRecording)
            }

            // Photo / video toggle
            modePicker
                .background(focusExclusionReporter(expand: 20, active: !cameraModel.isRecording))
                .padding(.bottom, 12)
                .hideWhileRecording(cameraModel.isRecording)

            // Capture bar (gallery / shutter / settings). Only the shutter
            // stays visible while recording; gallery + settings fade out so the
            // viewfinder reads as a single-purpose stop-recording surface.
            HStack {
                galleryButton
                    .hideWhileRecording(cameraModel.isRecording)
                Spacer()
                captureButton
                Spacer()
                settingsButton
                    .hideWhileRecording(cameraModel.isRecording)
            }
            .frame(maxWidth: 420)
            // Same focus-exclusion treatment as the top bar so these taps reach
            // the buttons instead of the focus gesture underneath.
            .background(focusExclusionReporter(expand: 8))
        }
        .padding(.horizontal, 16)
        // Track the preview rect: the rows clear the letterbox bands and sit
        // inside the image with an even margin (falling back to the stable
        // safe area on screens where the preview fills the height).
        .padding(.top, max(stableSafeInsets.top + 8, letterbox + 12))
        .padding(.bottom, max(stableSafeInsets.bottom + 4, letterbox + 12))
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
                .foregroundStyle(cameraModel.isRecording ? .gray : .primary)
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
                .foregroundStyle((cameraModel.cameraPosition == .front || cameraModel.isRecording) ? .gray : .primary)
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
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassControlBackground(in: .rect(cornerRadius: 8))
        .accessibilityLabel("Recording: \(formatDuration(cameraModel.recordingDurationMs))")
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Pins the recording capsule to whichever edge is physically up for the
    /// current orientation, upright. On rotation it cross-fades between
    /// positions rather than swinging around.
    private var recordingIndicatorOverlay: some View {
        let device = orientation.orientation
        let alignment: Alignment
        let edge: Edge.Set
        let inset: CGFloat
        switch device {
        case .landscapeLeft:
            alignment = .leading;  edge = .leading;  inset = 12
        case .landscapeRight:
            alignment = .trailing; edge = .trailing; inset = 12
        case .portraitUpsideDown:
            alignment = .bottom;   edge = .bottom;   inset = stableSafeInsets.bottom + 8
        default:
            alignment = .top;      edge = .top;      inset = stableSafeInsets.top + 8
        }

        return recordingIndicator
            .rotationEffect(Utils.getRotationAngle(for: device))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(edge, inset)
            .allowsHitTesting(false)
            .id(device)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: device)
    }

    private var zoomCapsule: some View {
        Text(String(format: "%.1fx", cameraModel.zoomFactor))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 80, height: 30)
            .glassControlBackground(in: .capsule)
        .opacity(cameraModel.zoomFactor != 1.0 ? 1.0 : 0.0)
        .animation(.easeInOut, value: cameraModel.zoomFactor)
        .rotationEffect(Utils.getRotationAngle())
        // Enlarge the tap target well beyond the visible capsule so a tap
        // "mostly on" it still counts, and make that whole area tappable.
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
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
        // The capsule is invisible at 1.0x — don't let it silently swallow taps,
        // and don't carve a focus-exclusion hole there.
        .allowsHitTesting(cameraModel.zoomFactor != 1.0)
        .background(focusExclusionReporter(active: cameraModel.zoomFactor != 1.0))
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
                        (cameraModel.isSavingPhoto || cameraModel.isRecording || cameraModel.isSavingVideo)
                            ? .gray : .primary
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
        .disabled(cameraModel.isSavingPhoto || cameraModel.isRecording || cameraModel.isSavingVideo)
        .padding()
        .accessibilityLabel("Gallery")
        .accessibilityHint(cameraModel.isSavingPhoto ? "Saving photo" : "")
    }

    private var settingsButton: some View {
        Button(action: { nav.navigate(to: .settings) }) {
            Image(systemName: "gear")
                .font(.title2)
                .foregroundStyle((cameraModel.isRecording || cameraModel.isSavingVideo) ? .gray : .primary)
                .rotatesWithDevice(orientation)
                .padding()
                .glassControlBackground(in: Circle())
        }
        .disabled(cameraModel.isRecording || cameraModel.isSavingVideo)
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
                // Glass interior (sized to the ring's inner edge) so the live
                // image shows through instead of a solid white slab.
                Image("snapshutter")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .foregroundStyle(cameraModel.isPermissionGranted ? Color.white : Color.gray)
                    .frame(width: 72, height: 72)
                    .glassControlBackground(in: Circle())
                Circle()
                    .strokeBorder(cameraModel.isPermissionGranted ? Color.white : Color.gray, lineWidth: 4)
                    .frame(width: 80, height: 80)
            }
            .frame(width: 90, height: 90)
            .contentShape(Circle())
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
                // Standard iOS record control: white ring, glass interior, red
                // core that becomes a square while recording.
                Group {
                    if cameraModel.isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 36, height: 36)
                    }
                }
                .frame(width: 72, height: 72)
                .glassControlBackground(in: Circle())
                Circle()
                    .strokeBorder(cameraModel.isPermissionGranted ? Color.white : Color.gray, lineWidth: 4)
                    .frame(width: 80, height: 80)
            }
            .frame(width: 90, height: 90)
            .contentShape(Circle())
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

// MARK: - Focus exclusion

/// Collects the frames of overlaid controls (mode toggle, zoom capsule) that
/// should suppress tap-to-focus on the preview beneath them.
private struct FocusExclusionPreferenceKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Liquid Glass control background

private extension View {
    /// Applies a translucent, contrasting control background per the Apple HIG:
    /// Liquid Glass on iOS 26+, with an `.ultraThinMaterial` fallback on earlier
    /// versions (the deployment floor is iOS 18.5).
    ///
    /// Uses the CLEAR glass variant, not regular: these controls float over the
    /// live viewfinder, where regular glass renders as a near-opaque dark disc.
    /// Per the HIG, clear glass over media needs a dim layer beneath it for
    /// symbol legibility — hence the black tint inside the shape.
    ///
    /// The glass is intentionally NOT `.interactive()`: these backgrounds live
    /// inside `Button`s (and tap gestures), and interactive glass installs its
    /// own touch handling that swallows the button's tap. The enclosing control
    /// provides the interaction; this modifier is purely the visual background.
    @ViewBuilder
    func glassControlBackground(in shape: some Shape) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(.clear, in: shape)
                .background(.black.opacity(0.25), in: shape)
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

    /// Hides a control while video recording is active so only the shutter is
    /// visible. Opacity fades; hit-testing is disabled in lockstep so the
    /// invisible button can't be tapped.
    func hideWhileRecording(_ isRecording: Bool) -> some View {
        self
            .opacity(isRecording ? 0 : 1)
            .allowsHitTesting(!isRecording)
    }
}

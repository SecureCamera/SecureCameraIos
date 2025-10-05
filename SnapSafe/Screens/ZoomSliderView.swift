//
//  ZoomSliderView.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/4/25.
//

import SwiftUI

struct ZoomSliderView: View {
    @ObservedObject var cameraModel: CameraViewModel
    @Binding var isVisible: Bool
    let isPinching: Bool
    let zoomLevels: [CGFloat] = [0.5, 1.0, 2.0, 3.0, 5.0, 10.0]
    @State private var isDragging = false
    @State private var hideTimer: Timer?
    @State private var deviceOrientation = UIDevice.current.orientation
    @State private var lastDetentLevel: CGFloat?
    private let snapThreshold: CGFloat = 0.25
    private let hapticThreshold: CGFloat = 0.1

    var body: some View {
        VStack(spacing: 8) {
            // Current zoom level display
            Text(String(format: "%.1fx", cameraModel.zoomFactor))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .rotationEffect(Utils.getRotationAngle())
                .animation(.easeInOut, value: deviceOrientation)

            // Slider with graduated marks
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.green.opacity(0.6))
                        .frame(height: 4)

                    // Tick marks and labels (tappable)
                    ForEach(zoomLevels, id: \.self) { level in
                        VStack(spacing: 4) {
                            // Tick mark
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 2, height: level == 1.0 ? 20 : 12)

                            // Label
                            Text(formatZoomLabel(level))
                                .font(.system(size: 10, weight: level == 1.0 ? .bold : .regular))
                                .foregroundColor(.white)
                                .rotationEffect(Utils.getRotationAngle())
                                .animation(.easeInOut, value: deviceOrientation)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            handleTickTap(level: level)
                        }
                        .position(x: tickPosition(for: level, in: geometry.size.width), y: 30)
                    }

                    // Current position indicator
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .offset(x: currentPosition(in: geometry.size.width) - 10)
                }
                .frame(maxWidth: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            cancelHideTimer()
                            updateZoom(from: value.location.x, in: geometry.size.width)
                            checkAndTriggerHapticForDetent()
                        }
                        .onEnded { _ in
                            isDragging = false
                            lastDetentLevel = nil
                            snapToNearestDetent()
                            scheduleHide()
                        }
                )
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 50)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
        )
        .frame(height: 80)
        .transition(.opacity.combined(with: .scale))
        .onAppear {
            scheduleHide()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                  object: nil,
                                                  queue: .main) { _ in
                self.deviceOrientation = UIDevice.current.orientation
            }
        }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onChange(of: isVisible) { _, newValue in
            if newValue {
                scheduleHide()
            } else {
                cancelHideTimer()
            }
        }
        .onChange(of: isPinching) { _, newValue in
            if newValue {
                cancelHideTimer()
            } else {
                scheduleHide()
            }
        }
    }

    private func formatZoomLabel(_ level: CGFloat) -> String {
        if level < 1.0 {
            return String(format: "%.1fx", level)
        } else {
            return String(format: "%.0fx", level)
        }
    }

    private func tickPosition(for level: CGFloat, in width: CGFloat) -> CGFloat {
        let minZoom = cameraModel.minZoom
        let maxZoom = cameraModel.maxZoom
        let normalizedPosition = (level - minZoom) / (maxZoom - minZoom)
        return normalizedPosition * width
    }

    private func currentPosition(in width: CGFloat) -> CGFloat {
        let minZoom = cameraModel.minZoom
        let maxZoom = cameraModel.maxZoom
        let normalizedPosition = (cameraModel.zoomFactor - minZoom) / (maxZoom - minZoom)
        return normalizedPosition * width
    }

    private func updateZoom(from position: CGFloat, in width: CGFloat) {
        let normalizedPosition = max(0, min(1, position / width))
        let minZoom = cameraModel.minZoom
        let maxZoom = cameraModel.maxZoom
        let newZoom = minZoom + (normalizedPosition * (maxZoom - minZoom))

        Task {
            await cameraModel.zoom(factor: newZoom)
        }
    }

    private func handleTickTap(level: CGFloat) {
        cancelHideTimer()
        triggerHapticFeedback()
        Task {
            await cameraModel.zoom(factor: level)
        }
        scheduleHide()
    }

    private func checkAndTriggerHapticForDetent() {
        let currentZoom = cameraModel.zoomFactor

        // Find the closest detent
        var closestLevel: CGFloat?
        var minDistance = CGFloat.greatestFiniteMagnitude

        for level in zoomLevels {
            if level >= cameraModel.minZoom && level <= cameraModel.maxZoom {
                let distance = abs(currentZoom - level)
                if distance < minDistance {
                    minDistance = distance
                    closestLevel = level
                }
            }
        }

        // If we're close to a detent and it's different from the last one we triggered
        if let closest = closestLevel, minDistance <= hapticThreshold {
            if lastDetentLevel != closest {
                triggerHapticFeedback()
                lastDetentLevel = closest
            }
        } else {
            // We're not near any detent, clear the last one
            if minDistance > hapticThreshold * 2 {
                lastDetentLevel = nil
            }
        }
    }

    private func snapToNearestDetent() {
        let currentZoom = cameraModel.zoomFactor
        var closestLevel = currentZoom
        var minDistance = CGFloat.greatestFiniteMagnitude

        for level in zoomLevels {
            if level >= cameraModel.minZoom && level <= cameraModel.maxZoom {
                let distance = abs(currentZoom - level)
                if distance < minDistance && distance <= snapThreshold {
                    minDistance = distance
                    closestLevel = level
                }
            }
        }

        if closestLevel != currentZoom {
            triggerHapticFeedback()
            Task {
                await cameraModel.zoom(factor: closestLevel)
            }
        }
    }

    private func triggerHapticFeedback() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func scheduleHide() {
        guard !isDragging && !isPinching else { return }
        cancelHideTimer()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            guard !self.isDragging && !self.isPinching else { return }
            withAnimation {
                self.isVisible = false
            }
        }
    }

    func keepVisible() {
        cancelHideTimer()
    }

    private func cancelHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}

#Preview {
    @Previewable @State var isVisible = true

    ZStack {
        Color.cyan.ignoresSafeArea()

        VStack {
            Spacer()
            ZoomSliderView(
                cameraModel: CameraViewModel(),
                isVisible: $isVisible,
                isPinching: false
            )
            .padding(.bottom, 100)
        }
    }
}

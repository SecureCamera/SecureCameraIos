//
//  CameraZoomMapping.swift
//  SnapSafe
//

import AVFoundation
import Foundation

/// Maps user-facing ("display") zoom factors to the virtual camera device's
/// `videoZoomFactor` space.
///
/// On a virtual device (`builtInDualWideCamera` / `builtInTripleCamera`),
/// `videoZoomFactor` 1.0 is the ultra-wide lens at full FOV. The wide lens
/// engages at the first entry of `virtualDeviceSwitchOverVideoZoomFactors`
/// (typically 2.0) — that is what users see as "1.0x".
struct CameraZoomMapping: Equatable {
    let wideSwitchOverFactor: CGFloat
    let minDisplayZoom: CGFloat
    let maxDisplayZoom: CGFloat

    init(switchOverFactors: [CGFloat], maxDeviceZoom: CGFloat, displayZoomCap: CGFloat = 10.0) {
        // A switch-over <= 1.0 (none, zero, negative) means there is no
        // ultra-wide constituent: fall back to the identity mapping.
        let firstSwitchOver = switchOverFactors.first ?? 1.0
        let wide = firstSwitchOver > 1.0 ? firstSwitchOver : 1.0
        self.wideSwitchOverFactor = wide
        self.minDisplayZoom = 1.0 / wide
        self.maxDisplayZoom = min(maxDeviceZoom / wide, displayZoomCap)
    }

    /// Converts a display zoom (what the UI shows) to the device's
    /// `videoZoomFactor`, clamped to the device's valid range.
    func deviceZoom(forDisplayZoom displayZoom: CGFloat) -> CGFloat {
        clampedDisplayZoom(displayZoom) * wideSwitchOverFactor
    }

    /// Converts a `videoZoomFactor` back to the display zoom shown in the UI.
    func displayZoom(forDeviceZoom deviceZoom: CGFloat) -> CGFloat {
        deviceZoom / wideSwitchOverFactor
    }

    /// Clamps a display zoom to the displayable range.
    func clampedDisplayZoom(_ displayZoom: CGFloat) -> CGFloat {
        min(max(displayZoom, minDisplayZoom), maxDisplayZoom)
    }
}

extension CameraZoomMapping {
    /// Derives the mapping from a capture device. Only a virtual device whose
    /// widest constituent is the ultra-wide lens places display 1.0x at the
    /// first switch-over factor; every other device maps identically.
    init(device: AVCaptureDevice) {
        let switchOvers: [CGFloat]
        if device.constituentDevices.first?.deviceType == .builtInUltraWideCamera {
            switchOvers = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        } else {
            switchOvers = []
        }
        self.init(
            switchOverFactors: switchOvers,
            maxDeviceZoom: device.activeFormat.videoMaxZoomFactor
        )
    }
}

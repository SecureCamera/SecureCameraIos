//
//  getRotationAngle.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//

import SwiftUI
import UIKit

// Get rotation angle for control glyphs based on device orientation
public struct Utils {
    /// Live angle for the current physical device orientation (main-actor).
    @MainActor public static func getRotationAngle() -> Angle {
        getRotationAngle(for: UIDevice.current.orientation)
    }

    /// Pure mapping from a device orientation to the glyph rotation angle.
    /// Non-interface orientations (faceUp/faceDown/unknown) map to upright.
    public static func getRotationAngle(for orientation: UIDeviceOrientation) -> Angle {
        switch orientation {
        case .landscapeLeft:      return Angle(degrees: 90)
        case .landscapeRight:     return Angle(degrees: -90)
        case .portraitUpsideDown: return Angle(degrees: 180)
        default:                  return Angle(degrees: 0)
        }
    }
}

extension UIDeviceOrientation {
    func getRotationAngle() -> Double {
        switch self {
        case .portrait:
            return 90    // device upright → rotate 90° CW
        case .portraitUpsideDown:
            return 270   // device upside down → rotate 270° CW
        case .landscapeLeft:
            return 0     // device rotated left (home button right) → 0° rotation (natural)
        case .landscapeRight:
            return 180   // device rotated right (home button left) → 180° rotation
        default:
            return 90    // Default to portrait rotation if unknown
        }
    }
}

/// Publishes the physical device orientation for views that rotate glyphs in
/// place (iOS Camera style). Filters out faceUp/faceDown/unknown so the glyphs
/// don't snap upright when the device is laid flat.
@MainActor
public final class OrientationObserver: ObservableObject {
    @Published public private(set) var orientation: UIDeviceOrientation = .portrait
    // nonisolated(unsafe) allows deinit (which is nonisolated) to access the
    // token without a Sendable violation. Access is safe because deinit is
    // always the last use of the object.
    nonisolated(unsafe) private var token: NSObjectProtocol?

    public init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        orientation = Self.resolve(incoming: UIDevice.current.orientation, last: .portrait)
        token = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.orientation = Self.resolve(
                    incoming: UIDevice.current.orientation,
                    last: self.orientation
                )
            }
        }
    }

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }

    /// Pure: keep the incoming orientation when it is a usable interface
    /// orientation, otherwise retain the last known value.
    public nonisolated static func resolve(
        incoming: UIDeviceOrientation,
        last: UIDeviceOrientation
    ) -> UIDeviceOrientation {
        switch incoming {
        case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
            return incoming
        default:
            return last
        }
    }
}


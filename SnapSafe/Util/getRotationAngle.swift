//
//  getRotationAngle.swift
//  SnapSafe
//
//  Created by Adam Brown on 9/6/25.
//

import SwiftUI

// Get rotation angle for the zoom indicator based on device orientation
public struct Utils {
    @MainActor public static func getRotationAngle() -> Angle {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            return Angle(degrees: 90)
        case .landscapeRight:
            return Angle(degrees: -90)
        case .portraitUpsideDown:
            return Angle(degrees: 180)
        default:
            return Angle(degrees: 0) // Default to portrait
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


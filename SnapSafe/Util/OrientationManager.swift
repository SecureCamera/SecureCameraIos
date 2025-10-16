//
//  OrientationManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/14/25.
//

import SwiftUI

// NOTE: The single image view is the only place we're doing this now.
// subviews of that view (settings, share...) will be in landscape as well.
// Rotating back out of landscape should return us to the portrait orientation.

/// View modifier to control device orientation for specific views
struct DeviceRotationViewModifier: ViewModifier {
    let orientations: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDelegate.orientationLock = orientations

                // Force rotation if needed
                if orientations == .portrait {
                    UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                }

                // Request geometry update for iOS 16+
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))

                    // Update supported orientations for the view controller
                    if let viewController = windowScene.windows.first?.rootViewController {
                        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
            .onDisappear {
                // Reset to portrait when leaving
                AppDelegate.orientationLock = .portrait
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")

                // Request geometry update for iOS 16+
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))

                    // Update supported orientations for the view controller
                    if let viewController = windowScene.windows.first?.rootViewController {
                        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                }
            }
    }
}

extension View {
    /// Allows this view to support specific orientations
    func supportedOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        modifier(DeviceRotationViewModifier(orientations: orientations))
    }
}

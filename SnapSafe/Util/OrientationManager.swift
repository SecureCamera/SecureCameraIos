//
//  OrientationManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/14/25.
//

import SwiftUI

// NOTE: The camera asserts `.portrait` and the single image view asserts
// `.allButUpsideDown`; other screens inherit the current lock. Rotation is
// driven through the supported `UIWindowScene.requestGeometryUpdate(_:)` API —
// do NOT set `UIDevice.orientation` directly (a private, unsupported hack that
// iOS rejects on-device with a "BUG IN CLIENT OF UIKIT" log).

/// View modifier to control device orientation for specific views
struct DeviceRotationViewModifier: ViewModifier {
    let orientations: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppDelegate.orientationLock = orientations

                // Force the interface to the requested orientations via the
                // supported API. The root VC re-reports its supported set first,
                // then the scene geometry request performs the actual rotation.
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?
                        .setNeedsUpdateOfSupportedInterfaceOrientations()
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
                }
            }
            .onDisappear {
                // Reset to portrait when leaving
                AppDelegate.orientationLock = .portrait

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?
                        .setNeedsUpdateOfSupportedInterfaceOrientations()
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
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

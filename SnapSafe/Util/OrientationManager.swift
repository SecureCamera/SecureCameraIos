//
//  OrientationManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/14/25.
//

import SwiftUI

// NOTE: The camera asserts `.portrait`, the gallery asserts `.allButUpsideDown`,
// and the single image / video detail view asserts `.allButUpsideDown`. Each
// modifier-bearing view declares its supported orientations on appear; on
// disappear we do NOT reset, so the next appearing view's onAppear owns the
// orientation without an intermediate portrait flash. Screens without a
// modifier inherit whatever the previous screen set; AppDelegate's default
// of `.portrait` covers the very first appearance at app launch.
//
// Rotation is driven through the supported `UIWindowScene.requestGeometryUpdate(_:)`
// API — do NOT set `UIDevice.orientation` directly (a private, unsupported hack
// that iOS rejects on-device with a "BUG IN CLIENT OF UIKIT" log).

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
    }
}

extension View {
    /// Allows this view to support specific orientations
    func supportedOrientations(_ orientations: UIInterfaceOrientationMask) -> some View {
        modifier(DeviceRotationViewModifier(orientations: orientations))
    }
}

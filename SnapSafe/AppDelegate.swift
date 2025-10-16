//
//  AppDelegate.swift
//  SnapSafe
//
//  Created by Bill Booth on 10/14/25.
//

import UIKit

// This allows us to rotate to landscape in the single picture view.

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

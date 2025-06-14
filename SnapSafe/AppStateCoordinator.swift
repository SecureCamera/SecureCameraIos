//
//  AppStateCoordinator.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import Combine
import SwiftUI

class AppStateCoordinator: ObservableObject {
    // Singleton instance
    static let shared = AppStateCoordinator()

    // Published properties
    @Published var needsAuthentication = false
    @Published var wasInBackground = false
    @Published var dismissAllSheets = false

    // Reference to PIN Manager
    private let pinManager = PINManager.shared

    // Subscriptions to manage cleanup
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Listen for scene phase notifications via NotificationCenter as a backup mechanism
        // This ensures we catch transitions even in modal sheets
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleDidEnterBackground()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleWillEnterForeground()
            }
            .store(in: &cancellables)

        print("AppStateCoordinator initialized")
    }

    // Handle when app enters background
    func handleDidEnterBackground() {
        print("App entered background")
        wasInBackground = true
    }

    // Handle when app will enter foreground
    func handleWillEnterForeground() {
        print("App will enter foreground, wasInBackground: \(wasInBackground)")
        if wasInBackground, pinManager.isPINSet, pinManager.requirePINOnResume {
            // Need to dismiss any open sheets and show authentication
            print("Requiring authentication after background")
            dismissAllSheets = true

            // Slight delay to ensure sheets are dismissed first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.needsAuthentication = true
            }
        }

        // Update last active time
        pinManager.updateLastActiveTime()
    }

    // Reset authentication state
    func resetAuthenticationState() {
        needsAuthentication = false
        wasInBackground = false
        dismissAllSheets = false
    }

    // Signal that authentication is complete
    func authenticationComplete() {
        needsAuthentication = false
        wasInBackground = false
    }
}

// ViewModifier to handle app state transitions
struct AppStateHandler: ViewModifier {
    @ObservedObject private var coordinator = AppStateCoordinator.shared
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: coordinator.dismissAllSheets) { _, shouldDismiss in
                if shouldDismiss {
                    // Dismiss this sheet
                    isPresented = false
                }
            }
    }
}

extension View {
    // Apply app state handling to modal sheets
    func handleAppState(isPresented: Binding<Bool>) -> some View {
        modifier(AppStateHandler(isPresented: isPresented))
    }
}

//
//  AppNavigation.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import SwiftUI

// MARK: - Navigation Destinations

enum AppDestination: Hashable {
    case settings
    case gallery
    case pinSetup
    case pinVerification
    case camera
}

// MARK: - Navigation State

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: AppDestination?
    @Published var presentedFullScreenCover: AppDestination?
    
    // MARK: - Navigation Methods
    
    func navigate(to destination: AppDestination) {
        navigationPath.append(destination)
    }
    
    func navigateBack() {
        if !navigationPath.isEmpty {
            navigationPath.removeLast()
        }
    }
    
    func navigateToRoot() {
        navigationPath.removeLast(navigationPath.count)
    }
    
    func presentSheet(_ destination: AppDestination) {
        presentedSheet = destination
    }
    
    func presentFullScreenCover(_ destination: AppDestination) {
        presentedFullScreenCover = destination
    }
    
    func dismissSheet() {
        presentedSheet = nil
    }
    
    func dismissFullScreenCover() {
        presentedFullScreenCover = nil
    }
    
    func dismissAll() {
        presentedSheet = nil
        presentedFullScreenCover = nil
        navigateToRoot()
    }
}

// MARK: - Navigation Extensions

extension View {
    func handleAppNavigation(navigationState: AppNavigationState) -> some View {
        self
            .sheet(item: Binding(
                get: { navigationState.presentedSheet },
                set: { _ in navigationState.dismissSheet() }
            )) { destination in
                navigationDestination(for: destination)
                    .obscuredWhenInactive()
                    .screenCaptureProtected()
            }
            .fullScreenCover(item: Binding(
                get: { navigationState.presentedFullScreenCover },
                set: { _ in navigationState.dismissFullScreenCover() }
            )) { destination in
                navigationDestination(for: destination)
                    .obscuredWhenInactive()
                    .screenCaptureProtected()
            }
    }
    
    @ViewBuilder
    private func navigationDestination(for destination: AppDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .gallery:
            NavigationStack {
                SecureGalleryView(onDismiss: {
                    // This will be handled by the parent view
                })
            }
        case .pinSetup:
            PINSetupView(isPINSetupComplete: .constant(false))
        case .pinVerification:
            PINVerificationView()
        case .camera:
            EmptyView() // Camera is handled in main view
        }
    }
}

// MARK: - AppDestination Identifiable Conformance

extension AppDestination: Identifiable {
    var id: String {
        switch self {
        case .settings: return "settings"
        case .gallery: return "gallery"
        case .pinSetup: return "pinSetup"
        case .pinVerification: return "pinVerification"
        case .camera: return "camera"
        }
    }
}

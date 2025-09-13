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
    case photoObfuscation(PhotoDef)
    case poisonPillSetupWizard
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
    
    func clearNavigationStack() {
        navigationPath.removeLast(navigationPath.count)
        dismissSheet()
        dismissFullScreenCover()
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
        case .photoObfuscation(let photoDef): return "photoObfuscation_\(photoDef.photoName)"
        case .poisonPillSetupWizard: return "poisonPillSetupWizard"
        }
    }
}

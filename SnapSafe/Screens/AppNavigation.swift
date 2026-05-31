//
//  AppNavigation.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import SwiftUI
import FactoryKit

// MARK: - Navigation Destinations

enum AppDestination: Hashable {
    case settings
    case gallery
    case pinSetup
    case pinVerification
    case camera
    case photoDetail(allMedia: [GalleryMediaItem], initialIndex: Int)
    case photoInfo(PhotoDef)
    case photoObfuscation(PhotoDef)
    case poisonPillSetupWizard
    case videoPlayer(VideoDef, Data?)
    case videoExportTest // For testing video export on simulator
}

// MARK: - Navigation State

@MainActor
final class AppNavigationState: ObservableObject {
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    @Published var navigationPath = NavigationPath()
    @Published var presentedSheet: AppDestination?
    @Published var presentedFullScreenCover: AppDestination?
    
    // MARK: - Navigation Methods
    
    func navigate(to destination: AppDestination) {
        authorizationRepository.keepAliveSession()
        
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
        case .photoDetail(_, let initialIndex): return "photoDetail_\(initialIndex)"
        case .photoInfo(let photoDef): return "photoInfo_\(photoDef.photoName)"
        case .photoObfuscation(let photoDef): return "photoObfuscation_\(photoDef.photoName)"
        case .poisonPillSetupWizard: return "poisonPillSetupWizard"
        case .videoPlayer(let videoDef, _): return "videoPlayer_\(videoDef.videoName)"
        case .videoExportTest: return "videoExportTest"
        }
    }
}

//
//  ContentView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/2/25.
//

import AVFoundation
import CoreGraphics
import CryptoKit
import ImageIO
import PhotosUI
import SwiftUI
import FactoryKit

// Notification name for opening camera from App Intent
extension Notification.Name {
    static let openCamera = Notification.Name("com.snapsafe.openCamera")
}


struct ContentView: View { 
    @StateObject private var viewModel = ContentViewModel()
    @InjectedObject(\.locationRepository) private var locationManager: LocationRepository

    @EnvironmentObject private var nav: AppNavigationState

    var body: some View {
        NavigationStack(path: $nav.navigationPath) {
            // Root view - navigation destinations will be pushed onto this
            Color.clear
                .navigationBarHidden(true)
                .navigationDestination(for: AppDestination.self) { destination in
                    navigationDestinationView(for: destination)
                        .navigationBarHidden(shouldHideNavigationBar(for: destination))
                }
        }
        .sheet(item: $nav.presentedSheet) { destination in
            navigationDestinationView(for: destination)
                .securityManaged()
        }
        .fullScreenCover(item: $nav.presentedFullScreenCover) { destination in
            navigationDestinationView(for: destination)
                .securityManaged()
        }
        .securityManaged()
        .onAppear {
            viewModel.onAppear()
            navigateToRootDestination()
        }
        .onChange(of: viewModel.hasCompletedIntro) { _, _ in
            navigateToRootDestination()
        }
        .onChange(of: viewModel.isAuthenticated) { _, _ in
            navigateToRootDestination()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCamera)) { _ in
            // Handle camera intent from Action Button
            if viewModel.isAuthenticated {
                nav.clearNavigationStack()
                nav.navigate(to: .camera)
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    private func navigateToRootDestination() {
        // Clear current navigation path and navigate to root destination
        nav.clearNavigationStack()
        nav.navigate(to: currentRootDestination)
    }
    
    private var currentRootDestination: AppDestination {
        #if DEBUG
        if CommandLine.arguments.contains("-SkipAuthentication") {
            return .camera
        }
        #endif
        if viewModel.hasCompletedIntro == false {
            return .pinSetup
        } else if !viewModel.isAuthenticated {
            return .pinVerification
        } else {
            return .camera
        }
    }
    
    // MARK: - Navigation Helper Methods

    private func shouldHideNavigationBar(for destination: AppDestination) -> Bool {
        switch destination {
        case .gallery, .photoObfuscation, .settings, .videoExportTest:
            return false
        case .videoPlayer:
            return true
        default:
            return true
        }
    }

    // MARK: - Navigation Destination Views

    @ViewBuilder
    private func navigationDestinationView(for destination: AppDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .gallery:
            SecureGalleryView(onDismiss: {
                nav.navigateBack()
            })
        case .pinSetup:
            PINSetupIntroView()
        case .pinVerification:
            PINVerificationView()
        case .camera:
            CameraContainerView()
        case .photoDetail(let allPhotos, let initialIndex):
            EnhancedPhotoDetailView(
                allPhotos: allPhotos,
                initialIndex: initialIndex,
                onDelete: nil,
                onDismiss: nil
            )
        case .photoInfo(let photoDef):
            ImageInfoView(photoDef: photoDef)
        case .photoObfuscation(let photoDef):
            PhotoObfuscationView(photoDef: photoDef, navigator: nav)
        case .poisonPillSetupWizard:
            PoisonPillSetupWizardView()
        case .videoPlayer(let videoDef, let keyData):
            VideoPlayerView(
                videoDef: videoDef,
                encryptionKey: keyData.map { SymmetricKey(data: $0) }
            )
        case .videoExportTest:
            if #available(iOS 18.0, *) {
                VideoExportTestView()
            } else {
                Text("Video Export Testing requires iOS 18+")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

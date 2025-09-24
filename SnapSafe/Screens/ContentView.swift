//
//  ContentView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/2/25.
//

import AVFoundation
import CoreGraphics
import ImageIO
import PhotosUI
import SwiftUI
import FactoryKit


struct ContentView: View { 
    @StateObject private var viewModel = ContentViewModel()
    @InjectedObject(\.locationRepository) private var locationManager: LocationRepository
    @InjectedObject(\.securityOverlayViewModel) private var securityViewModel: SecurityOverlayViewModel
    @EnvironmentObject private var nav: AppNavigationState

    var body: some View {
        NavigationStack(path: $nav.navigationPath) {
            // Root view - navigation destinations will be pushed onto this
            Color.clear
                .navigationBarHidden(true)
                .navigationDestination(for: AppDestination.self) { destination in
                    navigationDestinationView(for: destination)
                        .navigationBarHidden(destination != .gallery)
                }
        }
        .sheet(item: $nav.presentedSheet) { destination in
            navigationDestinationView(for: destination)
        }
        .fullScreenCover(item: $nav.presentedFullScreenCover) { destination in
            navigationDestinationView(for: destination)
        }
        // Apply unified security management
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
        .onChange(of: securityViewModel.dismissAllSheets) { _, shouldDismiss in
            if shouldDismiss {
                nav.dismissAll()
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
        if viewModel.hasCompletedIntro == false {
            return .pinSetup
        } else if !viewModel.isAuthenticated {
            return .pinVerification
        } else {
            return .camera
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
                nav.dismissFullScreenCover()
            })
        case .pinSetup:
            PINSetupIntroView()
        case .pinVerification:
            PINVerificationView()
        case .camera:
            CameraContainerView()
        case .photoObfuscation(let photoDef):
            PhotoObfuscationView(photoDef: photoDef, navigator: nav)
        case .poisonPillSetupWizard:
            PoisonPillSetupWizardView()
        }
    }
}

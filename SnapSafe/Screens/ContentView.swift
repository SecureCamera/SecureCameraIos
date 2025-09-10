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
                    navigationDestinationView(for: destination, isPINSetupComplete: $viewModel.isPINSetupComplete)
                        .navigationBarHidden(destination != .gallery)
                        .onChange(of: viewModel.isAuthenticated) { _, authenticated in
                            // Handle authentication changes for PIN verification
                            if destination == .pinVerification {
                                viewModel.handleAuthenticationChange(authenticated)
                            }
                        }
                }
        }
        .sheet(item: $nav.presentedSheet) { destination in
            navigationDestinationView(for: destination, isPINSetupComplete: $viewModel.isPINSetupComplete)
        }
        .fullScreenCover(item: $nav.presentedFullScreenCover) { destination in
            navigationDestinationView(for: destination, isPINSetupComplete: $viewModel.isPINSetupComplete)
        }
        // Apply unified security management
        .securityManaged()
        .onAppear {
            viewModel.onAppear()
        }
        .onChange(of: securityViewModel.dismissAllSheets) { _, shouldDismiss in
            if shouldDismiss {
                nav.dismissAll()
            }
        }
    }
    
    // MARK: - Navigation Destination Views
    
    @ViewBuilder
    private func navigationDestinationView(for destination: AppDestination, isPINSetupComplete: Binding<Bool>) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .gallery:
            SecureGalleryView(onDismiss: {
                nav.dismissFullScreenCover()
            })
        case .pinSetup:
            PINSetupView(isPINSetupComplete: isPINSetupComplete)
        case .pinVerification:
            PINVerificationView()
        case .camera:
            CameraContainerView()
        }
    }
}

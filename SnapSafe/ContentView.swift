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
    @StateObject private var locationManager = LocationManager.shared
    @ObservedObject private var appStateCoordinator = AppStateCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $viewModel.navigationState.navigationPath) {
            // Root view - navigation destinations will be pushed onto this
            Color.clear
                .navigationBarHidden(true)
                .navigationDestination(for: AppDestination.self) { destination in
                    viewModel.navigationDestinationView(for: destination, isPINSetupComplete: $viewModel.isPINSetupComplete)
                        .navigationBarHidden(true)
                        .onChange(of: viewModel.isAuthenticated) { _, authenticated in
                            // Handle authentication changes for PIN verification
                            if destination == .pinVerification {
                                viewModel.handleAuthenticationChange(authenticated)
                            }
                        }
                }
        }
        .sheet(item: Binding(
            get: { viewModel.navigationState.presentedSheet },
            set: { _ in viewModel.navigationState.dismissSheet() }
        )) { destination in
            viewModel.navigationDestinationView(for: destination, isPINSetupComplete: $viewModel.isPINSetupComplete)
                .obscuredWhenInactive()
                .screenCaptureProtected()
        }
        .fullScreenCover(item: Binding(
            get: { viewModel.navigationState.presentedFullScreenCover },
            set: { _ in viewModel.navigationState.dismissFullScreenCover() }
        )) { destination in
            viewModel.navigationDestinationView(for: destination, isPINSetupComplete: $viewModel.isPINSetupComplete)
                .obscuredWhenInactive()
                .screenCaptureProtected()
        }
        // Apply privacy shield when app is inactive (task switcher, control center, etc.)
        .obscuredWhenInactive()
        // Protect against screen recording and screenshots
        .screenCaptureProtected()
        .onAppear {
            viewModel.onAppear()
        }
        // Scene phase monitoring for background/foreground transitions
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
    }
}

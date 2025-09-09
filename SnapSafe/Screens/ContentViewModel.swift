//
//  ContentViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import SwiftUI
import Combine
import FactoryKit

@MainActor
final class ContentViewModel: ObservableObject {
    // MARK: - Published Properties
    private let navigationState = Container.shared.appNavigation()
    
    @Published var isPINSetupComplete = false
    @Published var hasCompletedIntro: Bool = false
    @Published var isAuthenticated: Bool = false
    
    // MARK: - Dependencies
    
    @Injected(\.settingsDataSource) 
    private var settings: SettingsDataSource
    
    @Injected(\.authorizationRepository) 
    private var authorizationRepository: AuthorizationRepository
    
    @Injected(\.securityOverlayViewModel)
    private var securityViewModel: SecurityOverlayViewModel
    
    @Injected(\.locationRepository)
    private var locationManager: LocationRepository
    
    private let screenCaptureManager = ScreenCaptureManager.shared
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        print("ContentView appeared - PIN is set: \(hasCompletedIntro), is authorized: \(isAuthenticated)")
        
        // Check session validity if PIN setup is complete
        if hasCompletedIntro {
            Task {
                await authorizationRepository.checkSessionValidity()
            }
        }
        
        // Navigate to appropriate root destination
        navigateToRootDestination()
    }
    
    func navigateToRootDestination() {
        // Clear current navigation path and navigate to root destination
        navigationState.navigateToRoot()
        navigationState.navigate(to: currentRootDestination)
    }
    
    func handlePINSetupComplete(_ completed: Bool) {
        if completed {
            print("PIN setup complete, authenticating user")
            // Reset flag to avoid issues on subsequent launches
            Task {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                isPINSetupComplete = false
            }
        }
    }
    
    
    func handleAuthenticationChange(_ authenticated: Bool) {
        if authenticated {
            // Reset the security overlay auth state when authenticated
            securityViewModel.authenticationComplete()
        }
    }
    
    // MARK: - Computed Properties
    
    var currentRootDestination: AppDestination {
        if hasCompletedIntro == false {
            return .pinSetup
        } else if !isAuthenticated {
            return .pinVerification
        } else {
            return .camera
        }
    }
    
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Monitor hasCompletedIntro from settings
        settings.hasCompletedIntro
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completed in
                let previousDestination = self?.currentRootDestination
                self?.hasCompletedIntro = completed
                // Navigate if root destination changed
                if previousDestination != self?.currentRootDestination {
                    self?.navigateToRootDestination()
                }
            }
            .store(in: &cancellables)
        
        // Monitor isAuthorized from authorization repository
        authorizationRepository.isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                let previousDestination = self?.currentRootDestination
                self?.isAuthenticated = authorized
                // Navigate if root destination changed
                if previousDestination != self?.currentRootDestination {
                    self?.navigateToRootDestination()
                }
            }
            .store(in: &cancellables)
        
    }
}

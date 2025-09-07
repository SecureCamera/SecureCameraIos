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
    
    @Injected(\.appStateCoordinator)
    private var appStateCoordinator: AppStateCoordinator
    
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
    
    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        print("ContentView scene phase changed to: \(newPhase)")
        Task {
            switch newPhase {
            case .active:
                // App is becoming active - let coordinator handle this
                await appStateCoordinator.handleWillEnterForeground()
            case .background:
                // App is going to background - let coordinator handle this
                appStateCoordinator.handleDidEnterBackground()
            case .inactive:
                // Transitional state
                print("App becoming inactive")
            @unknown default:
                break
            }
        }
    }
    
    func handleAuthenticationChange(_ authenticated: Bool) {
        if authenticated {
            // Reset the coordinator's auth state when authenticated
            appStateCoordinator.authenticationComplete()
        }
    }
    
    // MARK: - Computed Properties
    
    var currentRootDestination: AppDestination {
        if hasCompletedIntro == false {
            return .pinSetup
        } else if !isAuthenticated || appStateCoordinator.needsAuthentication {
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
        
        // Monitor authentication state from coordinator
        appStateCoordinator.$needsAuthentication
            .receive(on: DispatchQueue.main)
            .sink { [weak self] needsAuth in
                if needsAuth {
                    // Revoke authorization through the repository
                    self?.authorizationRepository.revokeAuthorization()
                }
            }
            .store(in: &cancellables)
        
        // Monitor dismiss all sheets signal
        appStateCoordinator.$dismissAllSheets
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldDismiss in
                if shouldDismiss {
                    // Dismiss all navigation
                    self?.navigationState.dismissAll()
                    
                    // Reset flag after a short delay
                    Task {
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        self?.appStateCoordinator.resetAuthenticationState()
                    }
                }
            }
            .store(in: &cancellables)
    }
}

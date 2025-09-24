//
//  ContentViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import SwiftUI
import Combine
import FactoryKit
import Logging

@MainActor
final class ContentViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var hasCompletedIntro: Bool = false
    @Published var isAuthenticated: Bool = false
    
    // MARK: - Dependencies
    
    @Injected(\.settingsDataSource) 
    private var settings: SettingsDataSource
    
    @Injected(\.authorizationRepository) 
    private var authorizationRepository: AuthorizationRepository
    
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
        Logger.ui.info("ContentView appeared", metadata: [
            "pinIsSet": .stringConvertible(hasCompletedIntro),
            "isAuthorized": .stringConvertible(isAuthenticated)
        ])
        
        // Check session validity if PIN setup is complete
        if hasCompletedIntro {
            Task {
                await authorizationRepository.checkSessionValidity()
            }
        }
        
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Monitor hasCompletedIntro from settings
        settings.hasCompletedIntro
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completed in
                self?.hasCompletedIntro = completed
            }
            .store(in: &cancellables)
        
        // Monitor isAuthorized from authorization repository
        authorizationRepository.isAuthorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                self?.isAuthenticated = authorized
            }
            .store(in: &cancellables)
    }
}

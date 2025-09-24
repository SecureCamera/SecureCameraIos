//
//  SettingsViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import Combine
import CoreLocation
import Foundation
import SwiftUI
import FactoryKit


@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    
    // Sharing options
    @Published var sanitizeFileName = true
    @Published var sanitizeMetadata = true
    
    // Security settings
    @Published var sessionTimeout = 5 // minutes
    @Published var appPIN = ""
    @Published var confirmAppPIN = ""
    @Published var poisonPIN = ""
    @Published var showResetConfirmation = false
    @Published var hasPoisonPill = false
    @Published var showRemovePoisonPillConfirmation = false
    @Published var showPINError = false
    @Published var pinErrorMessage = ""
    @Published var showPINSuccess = false
    
    // Decoy photos
    @Published var isSelectingDecoys = false
    
    // Location permissions
    @Published var locationPermissionStatus = "Not Determined"
    @Published var includeLocationData = false
    @Published var shouldOpenSettings = false
    
    // MARK: - Dependencies
    
    @Injected(\.pinRepository)
    private var pinRepository: PinRepository
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    @Injected(\.locationRepository)
    private var locationManager: LocationRepository
    
    @Injected(\.securityResetUseCase)
    private var securityResetUseCase: SecurityResetUseCase
    
    @Injected(\.createPoisonPillUseCase)
    private var createPoisonPillUseCase: CreatePoisonPillUseCase
    
    @Injected(\.settingsDataSource)
    private var settingsDataSource: SettingsDataSource
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        setupObservers()
        loadInitialValues()
    }
    
    // MARK: - Public Methods
    
    /// Initialize values when the view appears
    func onAppear() {
        includeLocationData = locationManager.shouldIncludeLocationData
        checkPoisonPillStatus()
    }
    
    /// Update sanitize file name setting
    func updateSanitizeFileName(_ newValue: Bool) {
        sanitizeFileName = newValue
        print("Sanitize file name: \(newValue)")
        Task {
            await settingsDataSource.setSanitizeFileName(newValue)
        }
    }
    
    /// Update sanitize metadata setting
    func updateSanitizeMetadata(_ newValue: Bool) {
        sanitizeMetadata = newValue
        print("Sanitize metadata: \(newValue)")
        Task {
            await settingsDataSource.setSanitizeMetadata(newValue)
        }
    }
    
    /// Request location permission or open settings
    func requestLocationPermission() {
        let permissionNotDetermined = locationManager.authorizationStatus == .notDetermined
        
        if permissionNotDetermined {
            locationManager.requestLocationPermission()
        } else {
            shouldOpenSettings = true
        }
    }
    
    /// Update session timeout setting
    func updateSessionTimeout(_ newValue: Int) {
        sessionTimeout = newValue
        print("Session timeout changed to \(newValue) minutes")
        Task {
            let newTimeoutMs: Int64 = Int64(newValue * 60 * 1000)
            await settingsDataSource.setSessionTimeout(newTimeoutMs)
        }
    }
    
    /// Start decoy selection process
    func startSelectingDecoys() {
        isSelectingDecoys = true
    }
    
    /// Stop decoy selection process
    func stopSelectingDecoys() {
        isSelectingDecoys = false
    }
    
    /// Save poisin pill PIN
    func savePoisonPillPIN() {
        if !poisonPIN.isEmpty {
            Task {
                print("Setting poison pill PIN")
                _ = await createPoisonPillUseCase.createPin(pppin: poisonPIN)
                poisonPIN = ""
                checkPoisonPillStatus()
            }
        }
    }
    
    /// Check if poison pill is currently configured
    func checkPoisonPillStatus() {
        Task {
            let hasPoison = await pinRepository.hasPoisonPillPin()
            await MainActor.run {
                self.hasPoisonPill = hasPoison
            }
        }
    }
    
    /// Show confirmation before removing poison pill
    func doShowRemovePoisonPillConfirmation() {
        showRemovePoisonPillConfirmation = true
    }
    
    /// Remove the configured poison pill
    func removePoisonPill() {
        Task {
            await pinRepository.removePoisonPillPin()
            await MainActor.run {
                self.hasPoisonPill = false
            }
        }
    }
    
    /// Show security reset confirmation
    func showSecurityResetConfirmation() {
        showResetConfirmation = true
    }
    
    /// Reset all security settings to default values
    func resetSecuritySettings() {
        Task {
            await self.securityResetUseCase.reset()
        }
    }
    
    // MARK: - Computed Properties
    
    var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    var locationPermissionButtonText: String {
        let permissionNotDetermined = locationManager.authorizationStatus == .notDetermined
        return permissionNotDetermined 
            ? "Request Location Permission"
            : "Manage Permission in Settings"
    }
    
    var isUpdatePINButtonDisabled: Bool {
        appPIN.isEmpty || confirmAppPIN.isEmpty
    }
    
    var isSaveEmergencyPINDisabled: Bool {
        poisonPIN.isEmpty
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Observe sanitize file name setting
        settingsDataSource.sanitizeFileName
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.sanitizeFileName = newValue
            }
            .store(in: &cancellables)
        
        // Observe sanitize metadata setting
        settingsDataSource.sanitizeMetadata
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.sanitizeMetadata = newValue
            }
            .store(in: &cancellables)
        
        // Observe session timeout setting
        settingsDataSource.sessionTimeout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] timeoutMs in
                // Convert from milliseconds to minutes
                let timeoutMinutes = Int(timeoutMs / 60 / 1000)
                self?.sessionTimeout = timeoutMinutes
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialValues() {
        Task {
            // Load session timeout from settings
            let timeoutMs = await settingsDataSource.getSessionTimeout()
            let timeoutMinutes = Int(timeoutMs / 60 / 1000)
            
            await MainActor.run {
                self.sessionTimeout = timeoutMinutes
            }
            
            // Note: sanitizeFileName and sanitizeMetadata will be loaded via publishers
            // in setupObservers(), so we don't need to load them explicitly here
        }
        
        // Load location permission status
        locationPermissionStatus = locationStatusDisplayText(locationManager.authorizationStatus)
    }
    
    private func locationStatusDisplayText(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not Asked"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedWhenInUse:
            return "When In Use"
        case .authorizedAlways:
            return "Always"
        @unknown default:
            return "Unknown"
        }
    }
}

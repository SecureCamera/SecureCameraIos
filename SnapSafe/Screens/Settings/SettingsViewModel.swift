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
    
    // Privacy and detection options
    @Published var showFaceDetection = true
    
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
        // TODO: Update user preferences
    }
    
    /// Update sanitize metadata setting
    func updateSanitizeMetadata(_ newValue: Bool) {
        sanitizeMetadata = newValue
        print("Sanitize metadata: \(newValue)")
        // TODO: Update user preferences
    }
    
    /// Update face detection setting
    func updateFaceDetection(_ newValue: Bool) {
        showFaceDetection = newValue
        print("Face detection: \(newValue)")
    }
    
    /// Update include location data setting
    func updateIncludeLocationData(_ newValue: Bool) {
        includeLocationData = newValue
        locationManager.setIncludeLocationData(newValue)
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
        // TODO: Update user preferences
    }
    
    /// Update app PIN input with validation
    func updateAppPIN(_ newValue: String) {
        // Limit to 4 digits
        var filteredValue = newValue
        if filteredValue.count > 4 {
            filteredValue = String(filteredValue.prefix(4))
        }
        
        // Only allow numbers
        if !filteredValue.allSatisfy({ $0.isNumber }) {
            filteredValue = filteredValue.filter { $0.isNumber }
        }
        
        appPIN = filteredValue
        
        // Clear any previous errors when typing
        if showPINError {
            showPINError = false
        }
    }
    
    /// Update confirm app PIN input with validation
    func updateConfirmAppPIN(_ newValue: String) {
        // Limit to 4 digits
        var filteredValue = newValue
        if filteredValue.count > 4 {
            filteredValue = String(filteredValue.prefix(4))
        }
        
        // Only allow numbers
        if !filteredValue.allSatisfy({ $0.isNumber }) {
            filteredValue = filteredValue.filter { $0.isNumber }
        }
        
        confirmAppPIN = filteredValue
        
        // Clear any previous errors when typing
        if showPINError {
            showPINError = false
        }
    }
    
    /// Reset or change the app PIN
    /// TODO: We will need to implement Key rotation, but it untill we do, we cant just change the PIN
    func resetAppPIN() {
        // Reset any previous feedback
//        showPINError = false
//        showPINSuccess = false
//        
//        // Validate PIN
//        if appPIN.count != 4 {
//            showPINError = true
//            pinErrorMessage = "PIN must be 4 digits"
//            return
//        }
//        
//        // Check if PINs match
//        if appPIN != confirmAppPIN {
//            showPINError = true
//            pinErrorMessage = "PINs do not match"
//            return
//        }
//        
//        // Update the PIN using PIN manager
//        //pinManager.setPIN(appPIN)
//        
//        // Show success message
//        showPINSuccess = true
//        
//        // Clear the fields
//        appPIN = ""
//        confirmAppPIN = ""
//        
//        // Clear success message after delay
//        Task {
//            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
//            showPINSuccess = false
//        }
//        
//        print("App PIN has been updated")
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
                await createPoisonPillUseCase.createPin(pppin: poisonPIN)
                poisonPIN = ""
                checkPoisonPillStatus()
            }
        }
    }
    
    /// Check if poison pill is currently configured
    func checkPoisonPillStatus() {
        Task {
            do {
                let hasPoison = try await pinRepository.hasPoisonPillPin()
                await MainActor.run {
                    self.hasPoisonPill = hasPoison
                }
            } catch {
                print("Error checking poison pill status: \(error)")
                await MainActor.run {
                    self.hasPoisonPill = false
                }
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
        // Add any necessary observers for dependencies
    }
    
    private func loadInitialValues() {
        // Load any initial values from user defaults or other sources
    }
}

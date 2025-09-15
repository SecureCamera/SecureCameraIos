//
//  PINVerificationViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import Foundation
import SwiftUI
import FactoryKit
import Logging

@MainActor
final class PINVerificationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var pin = ""
    @Published var showError = false
    @Published var attempts = 0
    @Published var isLoading = false
    @Published var backoffSeconds = 0
    @Published var currentFailedAttempts = 0
    
    // MARK: - Timer
    private var backoffTimer: Timer?
    
    // MARK: - Dependencies
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    @Injected(\.securityOverlayViewModel)
    private var securityViewModel: SecurityOverlayViewModel
    
    @Injected(\.verifyPinUseCase)
    private var verifyPinUseCase: VerifyPinUseCase
    
    @Injected(\.securityResetUseCase)
    private var securityResetUseCase: SecurityResetUseCase
    
    
    // MARK: - Computed Properties
    
    var isUnlockButtonDisabled: Bool {
        pin.count < 4 || isLoading || backoffSeconds > 0
    }
    
    var unlockButtonBackgroundColor: Color {
        if pin.count >= 4 && !isLoading && backoffSeconds == 0 {
            // Red for final attempt, blue for normal attempts
            return isLastAttempt ? Color.red : Color.blue
        } else {
            return Color.gray
        }
    }
    
    var isLastAttempt: Bool {
        currentFailedAttempts >= (AuthorizationRepository.MAX_FAILED_ATTEMPTS - 1)
    }
    
    var unlockButtonText: String {
        if backoffSeconds > 0 {
            return "Wait (\(backoffSeconds)s)"
        } else if isLoading {
            return "Verifying..."
        } else {
            return "Unlock"
        }
    }
    
    var errorMessage: String {
        "Invalid PIN. Please try again."
    }
    
    var shouldShowAttemptsWarning: Bool {
        currentFailedAttempts > 2
    }
    
    var attemptsWarningMessage: String {
        let remaining = AuthorizationRepository.MAX_FAILED_ATTEMPTS - currentFailedAttempts
        return "Attempts \(remaining)/\(AuthorizationRepository.MAX_FAILED_ATTEMPTS)"
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        // Update last active time when view appears
        authorizationRepository.keepAliveSession()
        
        Task {
            await updateBackoffTime()
            await updateCurrentFailedAttempts()
        }
    }
    
    func onDisappear() {
        stopBackoffTimer()
    }
    
    func updatePIN(_ newValue: String) {
        // Limit to 4 digits
        var filteredValue = newValue
        if filteredValue.count > 4 {
            filteredValue = String(filteredValue.prefix(4))
        }
        
        // Only allow numbers
        if !filteredValue.allSatisfy({ $0.isNumber }) {
            filteredValue = filteredValue.filter { $0.isNumber }
        }
        
        pin = filteredValue
    }
    
    func verifyPIN() async {
        isLoading = true
        showError = false
        
        let success = await verifyPinUseCase.verifyPin(pin)
        
        isLoading = false
        
        if success {
            // PIN verification successful (includes poison pill handling)
            Logger.security.info("PIN verification successful")
            
            // Reset failed attempts counter on successful verification
            attempts = 0
            
            // Update current failed attempts from repository after successful verification
            Task {
                await updateCurrentFailedAttempts()
            }
            
            // Notify SecurityOverlayViewModel that authentication is complete
            securityViewModel.authenticationComplete()
            
            // Update UI state
            showError = false
            
            // Clear the PIN field for next time
            pin = ""
        } else {
            // PIN verification failed
            showError = true
            attempts += 1
            pin = ""
            
            Logger.security.warning("PIN verification failed", metadata: [
                "attemptCount": .stringConvertible(attempts),
                "maxAttempts": .stringConvertible(AuthorizationRepository.MAX_FAILED_ATTEMPTS)
            ])
            
            // Check if we've reached the maximum failed attempts
            if attempts >= AuthorizationRepository.MAX_FAILED_ATTEMPTS {
                Logger.security.critical("Maximum failed PIN attempts reached, triggering security reset", metadata: [
                    "attemptCount": .stringConvertible(attempts)
                ])
                
                // Trigger security reset
                Task {
                    await securityResetUseCase.reset()
                }
            } else {
                // Check for backoff time after failed attempt
                Task {
                    await updateBackoffTime()
                    await updateCurrentFailedAttempts()
                }
            }
        }
    }
    
    func unlockButtonTapped() {
        Task {
            await verifyPIN()
        }
    }
    
    // MARK: - Security Methods

    func clearPinContent() {
        pin = ""
        showError = false
    }

    // MARK: - Private Methods
    
    private func updateBackoffTime() async {
        let remainingSeconds = await authorizationRepository.calculateRemainingBackoffSeconds()
        
        await MainActor.run {
            self.backoffSeconds = remainingSeconds
            
            if remainingSeconds > 0 {
                startBackoffTimer()
                Logger.security.info("PIN verification backoff active", metadata: [
                    "backoffSeconds": .stringConvertible(remainingSeconds)
                ])
            } else {
                stopBackoffTimer()
            }
        }
    }
    
    private func updateCurrentFailedAttempts() async {
        let failedAttempts = await authorizationRepository.getFailedAttempts()
        
        await MainActor.run {
            self.currentFailedAttempts = failedAttempts
        }
    }
    
    private func startBackoffTimer() {
        stopBackoffTimer() // Stop any existing timer
        
        backoffTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if self.backoffSeconds > 0 {
                    self.backoffSeconds -= 1
                } else {
                    self.stopBackoffTimer()
                }
            }
        }
    }
    
    private func stopBackoffTimer() {
        backoffTimer?.invalidate()
        backoffTimer = nil
    }
}

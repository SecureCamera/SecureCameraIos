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
    @Published var showRetryableError = false
    @Published var isLoading = false
    @Published var backoffSeconds = 0
    @Published var failedAttempts = 0
    
    // MARK: - Timer
    private var backoffTimer: Timer?
    
    // MARK: - Dependencies
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    @Injected(\.verifyPinUseCase)
    private var verifyPinUseCase: VerifyPinUseCase
    
    @Injected(\.securityResetUseCase)
    private var securityResetUseCase: SecurityResetUseCase
    
    
    // MARK: - Computed Properties
    
    var isUnlockButtonDisabled: Bool {
        pin.count < MIN_PIN_LENGTH || isLoading || backoffSeconds > 0
    }
    
    var unlockButtonBackgroundColor: Color {
        if pin.count >= MIN_PIN_LENGTH && !isLoading && backoffSeconds == 0 {
            // Red for final attempt, blue for normal attempts
            return isLastAttempt ? Color.red : Color.blue
        } else {
            return Color.gray
        }
    }
    
    var isLastAttempt: Bool {
        failedAttempts >= (AuthorizationRepository.MAX_FAILED_ATTEMPTS - 1)
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

    var retryableErrorMessage: String {
        "Something went wrong unlocking. Please try again."
    }
    
    var shouldShowAttemptsWarning: Bool {
        failedAttempts > 2
    }
    
    var attemptsWarningMessage: String {
        let remaining = AuthorizationRepository.MAX_FAILED_ATTEMPTS - failedAttempts
        return "Attempts remaining \(remaining)/\(AuthorizationRepository.MAX_FAILED_ATTEMPTS)"
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
        // Limit to 10 digits
        var filteredValue = newValue
        if filteredValue.count > MAX_PIN_LENGTH {
            filteredValue = String(filteredValue.prefix(MAX_PIN_LENGTH))
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
        showRetryableError = false

        let result = await verifyPinUseCase.verifyPin(pin)

        isLoading = false

        switch result {
        case .success:
            // PIN verification successful (includes poison pill handling).
            // The repository already reset the counter to 0 on success
            // (AuthorizePinUseCase.resetFailedAttempts); just reflect that
            // locally rather than writing it a second time (M1).
            Logger.security.info("PIN verification successful")

            failedAttempts = 0

            // Update UI state
            showError = false
            showRetryableError = false

            // Clear the PIN field for next time
            pin = ""

        case .failure(let error):
            // Transient / retryable error during key derivation. Do NOT count
            // this against failed-attempts — otherwise an attacker who can race
            // the device-lock state can force a security reset (DoS).
            showRetryableError = true
            pin = ""

            Logger.security.error("PIN verification failed transiently", metadata: [
                "error": .string(String(describing: error))
            ])

        case .invalidPin(let failedAttempts):
            // PIN verification failed. The repository is the single writer of
            // the counter (and the backoff timestamp/baseline); the use case
            // already incremented and returns the authoritative count here.
            // We only reflect it — we never write it back (M1).
            showError = true
            self.failedAttempts = failedAttempts
            pin = ""

            Logger.security.warning("PIN verification failed", metadata: [
                "attemptCount": .stringConvertible(failedAttempts),
                "maxAttempts": .stringConvertible(AuthorizationRepository.MAX_FAILED_ATTEMPTS)
            ])

            // Check if we've reached the maximum failed attempts
            if failedAttempts >= AuthorizationRepository.MAX_FAILED_ATTEMPTS {
                Logger.security.critical("Maximum failed PIN attempts reached, triggering security reset", metadata: [
                    "attemptCount": .stringConvertible(failedAttempts)
                ])

                // Trigger security reset
                Task {
                    await securityResetUseCase.reset()
                }
            } else {
                Logger.security.info("Failed PIN verification", metadata: [
                    "attemptCount": .stringConvertible(failedAttempts)
                ])

                // Refresh backoff state after the failed attempt.
                Task {
                    await updateBackoffTime()
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
        let attempts = await authorizationRepository.getFailedAttempts()

        await MainActor.run {
            self.failedAttempts = attempts
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

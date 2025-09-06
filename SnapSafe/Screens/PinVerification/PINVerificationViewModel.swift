//
//  PINVerificationViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import Foundation
import SwiftUI
import FactoryKit

@MainActor
final class PINVerificationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var pin = ""
    @Published var showError = false
    @Published var attempts = 0
    
    // MARK: - Dependencies
    
    @Injected(\.authorizationRepository)
    private var authorizationRepository: AuthorizationRepository
    
    @Injected(\.authorizedPinUseCase)
    private var authorizePinUseCase: AuthorizePinUseCase
    
    // MARK: - Callbacks
    
    var onAuthenticationSuccess: (() -> Void)?
    var onAuthenticationFailure: (() -> Void)?
    
    // MARK: - Computed Properties
    
    var isUnlockButtonDisabled: Bool {
        pin.count != 4
    }
    
    var unlockButtonBackgroundColor: Color {
        pin.count == 4 ? Color.blue : Color.gray
    }
    
    var errorMessage: String {
        "Invalid PIN. Please try again."
    }
    
    // MARK: - Public Methods
    
    func onAppear() {
        // Update last active time when view appears
        authorizationRepository.keepAliveSession()
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
        let hashedPin = await authorizePinUseCase.authorizePin(pin)
        if hashedPin != nil {
            // PIN is correct - prioritize setting authentication flag
            // to trigger immediate transition
            print("PIN correct, transitioning immediately")
            
            // Update authentication state with high priority
            Task { @MainActor in
                self.showError = false
                
                // Clear the PIN field for next time
                self.pin = ""
                
                // Notify success
                self.onAuthenticationSuccess?()
            }
        } else {
            // PIN is incorrect
            showError = true
            attempts += 1
            pin = ""
            
            // Notify failure
            onAuthenticationFailure?()
            
            // Could add more sophisticated security measures here, like
            // temporary lockout after multiple failed attempts
        }
    }
    
    func unlockButtonTapped() {
        Task {
            await verifyPIN()
        }
    }
    
    // MARK: - Private Methods
    
    // Add any private helper methods if needed
}

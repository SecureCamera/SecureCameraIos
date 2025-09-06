//
//  PINVerificationViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/6/25.
//

import Foundation
import SwiftUI

@MainActor
final class PINVerificationViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var pin = ""
    @Published var showError = false
    @Published var attempts = 0
    
    // MARK: - Dependencies
    
    private let pinManager = PINManager.shared
    
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
        pinManager.updateLastActiveTime()
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
        
        // Auto-verify when 4 digits are entered
        if filteredValue.count == 4 {
            verifyPIN()
        }
    }
    
    func verifyPIN() {
        if pinManager.verifyPIN(pin) {
            // PIN is correct - prioritize setting authentication flag
            // to trigger immediate transition
            print("PIN correct, transitioning immediately")
            
            // Update authentication state with high priority
            Task { @MainActor in
                self.showError = false
                
                // Update last active time after transition has started
                self.pinManager.updateLastActiveTime()
                
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
        verifyPIN()
    }
    
    // MARK: - Private Methods
    
    // Add any private helper methods if needed
}
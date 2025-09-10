//
//  PINSetupViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/5/25.
//

import Foundation
import Combine
import FactoryKit

@MainActor
final class PINSetupViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var pin: String = ""
    @Published var confirmPin: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    
    // MARK: - Computed Properties
    var isPINValid: Bool {
        pin.count == 4 && confirmPin.count == 4
    }
    
    var canSubmit: Bool {
        isPINValid && !isLoading
    }
    
    // MARK: - Dependencies
    @Injected(\.createPinUseCase) private var createPinUseCase: CreatePinUseCase
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Clear error when user starts typing
        Publishers.CombineLatest($pin, $confirmPin)
            .sink { [weak self] _, _ in
                self?.clearError()
            }
            .store(in: &cancellables)
    }
    
    private func clearError() {
        showError = false
        errorMessage = ""
    }
    
    // MARK: - PIN Validation Methods
    func validateAndFilterPIN(_ newValue: String, isConfirm: Bool = false) -> String {
        var filtered = newValue
        
        // Only allow numbers
        filtered = filtered.filter { $0.isNumber }
        
        // Limit to 4 digits
        if filtered.count > 4 {
            filtered = String(filtered.prefix(4))
        }
        
        return filtered
    }
    
    func updatePIN(_ newValue: String) {
        pin = validateAndFilterPIN(newValue)
    }
    
    func updateConfirmPIN(_ newValue: String) {
        confirmPin = validateAndFilterPIN(newValue)
    }
    
    // MARK: - Business Logic
    func createPin() async -> Bool {
        guard canSubmit else { return false }
        
        isLoading = true
        defer { isLoading = false }
        
        // Validate PIN length
        if pin.count != 4 {
            showError(message: "PIN must be 4 digits")
            return false
        }
        
        // Check if PINs match
        if pin != confirmPin {
            showError(message: "PINs do not match")
            return false
        }
        
        // Validate PIN format (already done above, but keeping for clarity)
        guard pin.allSatisfy({ $0.isNumber }) else {
            showError(message: "PIN must contain only numbers")
            return false
        }
        
        // Create the PIN using the use case
        let success = await createPinUseCase.createPin(pin)
        
        if !success {
            showError(message: "Failed to create PIN. Please try again.")
            return false
        }
        
        return true
    }
    
    // MARK: - Error Handling
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
    
    // MARK: - Reset Methods
    func reset() {
        pin = ""
        confirmPin = ""
        clearError()
        isLoading = false
    }
}

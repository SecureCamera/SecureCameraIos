//
//  PINSetupViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/5/25.
//

import Foundation
import FactoryKit

@MainActor
final class PINSetupViewModel: ObservableObject {
    
    @Injected(\.settingsDataSource)
    private var settings: SettingsDataSource
    
    // MARK: - Published Properties
    @Published
    var pin: String = "" {
        didSet {
            let filtered = validateAndFilterPIN(pin)
            if pin != filtered {
                pin = filtered
            }
        }
    }
    
    @Published
    var confirmPin: String = "" {
        didSet {
            let filtered = validateAndFilterPIN(confirmPin)
            if confirmPin != filtered {
                confirmPin = filtered
            }
        }
    }
    
    @Published var isAlphanumeric: Bool = false

    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    // MARK: - Computed Properties
    var isPINValid: Bool {
        pin.count >= MIN_PIN_LENGTH && pin.count <= MAX_PIN_LENGTH
        && confirmPin.count >= MIN_PIN_LENGTH && confirmPin.count <= MAX_PIN_LENGTH
    }
    
    var canSubmit: Bool {
        isPINValid && !isLoading
    }
    
    // MARK: - Dependencies
    @Injected(\.createPinUseCase) private var createPinUseCase: CreatePinUseCase
    @Injected(\.pinStrengthCheckUseCase) private var pinStrengthCheckUseCase: PinStrengthCheckUseCase
    
    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
    }
    
    private func clearError() {
        showError = false
        errorMessage = ""
    }
    
    // MARK: - PIN Validation Methods
    func validateAndFilterPIN(_ newValue: String) -> String {
        var filtered = newValue

        // Allow letters and numbers for alphanumeric PINs, numbers only otherwise
        if isAlphanumeric {
            filtered = filtered.filter { $0.isLetter || $0.isNumber }
        } else {
            filtered = filtered.filter { $0.isNumber }
        }

        // Limit to max length
        if filtered.count > MAX_PIN_LENGTH {
            filtered = String(filtered.prefix(MAX_PIN_LENGTH))
        }

        return filtered
    }
    
    
    // MARK: - Business Logic
    func createPin() async -> Bool {
        guard canSubmit else { return false }
        
        clearError()
        
        isLoading = true
        defer { isLoading = false }
        
        // Check if PINs match
        if pin != confirmPin {
            showError(message: "PINs do not match")
            return false
        }
        
        let pinType: PINType = isAlphanumeric ? .alphanumeric : .numeric

        // Validate numeric-only format when not alphanumeric
        if !isAlphanumeric {
            guard pin.allSatisfy({ $0.isNumber }) else {
                showError(message: "PIN must contain only numbers")
                return false
            }
        }

        // Check PIN strength
        if !pinStrengthCheckUseCase.isPinStrongEnough(pin, pinType: pinType) {
            showError(message: isAlphanumeric
                ? "PIN is too weak. Avoid common words and repeated characters."
                : "PIN is too weak. Avoid common patterns like 1234 or repeated digits.")
            return false
        }

        // Create the PIN using the use case
        let success = await createPinUseCase.createPin(pin, pinType: pinType)
        
        if !success {
            showError(message: "Failed to create PIN. Please try again.")
            return false
        }
        
        await settings.setIntroCompleted(true)
        
        return true
    }
    
    // MARK: - Error Handling
    private func showError(message: String) {
        pin = ""
        confirmPin = ""
        
        errorMessage = message
        showError = true
    }
    
    func clearPinContent() {
        pin = ""
        confirmPin = ""
        clearError()
    }
}

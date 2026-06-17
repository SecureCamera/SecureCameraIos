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
    
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    /// Global alphanumeric-PIN preference, mirrored from settings. The setup
    /// screen is where this choice is made; it applies to the poison pill and
    /// the unlock screen too.
    @Published var isAlphanumeric: Bool = false

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
    
    // MARK: - Alphanumeric preference
    /// Seed the toggle from the persisted global setting.
    func loadAlphanumericSetting() async {
        isAlphanumeric = await settings.getAlphanumericPinEnabled()
    }

    /// Update and persist the global preference, re-filtering any entered text.
    func setAlphanumeric(_ enabled: Bool) {
        guard enabled != isAlphanumeric else { return }
        isAlphanumeric = enabled
        pin = validateAndFilterPIN(pin)
        confirmPin = validateAndFilterPIN(confirmPin)
        Task { await settings.setAlphanumericPinEnabled(enabled) }
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
        // Filter to the active PIN type: letters + digits when alphanumeric,
        // digits only otherwise.
        var filtered = isAlphanumeric
            ? newValue.filter { $0.isLetter || $0.isNumber }
            : newValue.filter { $0.isNumber }

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
        
        // Check PIN strength against the active (global) PIN type.
        if !pinStrengthCheckUseCase.isPinStrongEnough(pin, isAlphanumeric: isAlphanumeric) {
            showError(message: isAlphanumeric
                ? "PIN is too weak. Avoid common words and repeated characters."
                : "PIN is too weak. Avoid common patterns like 1234 or repeated digits.")
            return false
        }

        // Create the PIN using the use case
        let success = await createPinUseCase.createPin(pin)
        
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

//
//  PoisonPillSetupWizardViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/12/25.
//

import SwiftUI
import Combine
import FactoryKit
import Logging

enum PoisonPillWizardStep: Int, CaseIterable {
    case explanation1 = 0
    case explanation2 = 1
    case explanation3 = 2
    case pinCreation = 3
    
    var title: String {
        switch self {
        case .explanation1:
            return "Poison Pill"
        case .explanation2:
            return "How It Works"
        case .explanation3:
            return "Decoy Strategy"
        case .pinCreation:
            return "Set Poison Pill PIN"
        }
    }
}

@MainActor
final class PoisonPillSetupWizardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentStep: PoisonPillWizardStep = .explanation1
    @Published var pin: String = ""
    @Published var confirmPin: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isAlphanumeric: Bool = false

    // MARK: - Dependencies

    @Injected(\.createPoisonPillUseCase)
    private var createPoisonPillUseCase: CreatePoisonPillUseCase
    
    @Injected(\.pinStrengthCheckUseCase)
    private var pinStrengthCheckUseCase: PinStrengthCheckUseCase
    
    // MARK: - Computed Properties
    
    var canProceedFromPinCreation: Bool {
        return isPinLengthValid(pin.count) && 
               isPinLengthValid(confirmPin.count) && 
               pin == confirmPin &&
               !isLoading
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
    
    func isPinLengthValid(_ length: Int) -> Bool {
        return length >= MIN_PIN_LENGTH && length <= MAX_PIN_LENGTH
    }
    
    var progressValue: Double {
        Double(currentStep.rawValue + 1) / Double(PoisonPillWizardStep.allCases.count)
    }
    
    // MARK: - Navigation Methods
    
    func goToNextStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch currentStep {
            case .explanation1:
                currentStep = .explanation2
            case .explanation2:
                currentStep = .explanation3
            case .explanation3:
                currentStep = .pinCreation
            case .pinCreation:
                break // Already at the last step
            }
        }
    }
    
    func goToPreviousStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            switch currentStep {
            case .explanation1:
                break // Already at the first step
            case .explanation2:
                currentStep = .explanation1
            case .explanation3:
                currentStep = .explanation2
            case .pinCreation:
                currentStep = .explanation3
            }
        }
    }
    
    // MARK: - PIN Management
    
    func updatePIN(_ newValue: String) {
        let filtered = validateAndFilterPIN(newValue)
        if pin != filtered {
            pin = filtered
        }
    }
    
    func updateConfirmPIN(_ newValue: String) {
        let filtered = validateAndFilterPIN(newValue)
        if confirmPin != filtered {
            confirmPin = filtered
        }
    }
    
    func setupPoisonPillPIN() async -> Bool {
        guard canProceedFromPinCreation else { return false }
        
        isLoading = true
        showError = false

        let pinType: PINType = isAlphanumeric ? .alphanumeric : .numeric

        // Check PIN strength
        if !pinStrengthCheckUseCase.isPinStrongEnough(pin, pinType: pinType) {
            showError = true
            errorMessage = isAlphanumeric
                ? "PIN is too weak. Avoid common words and repeated characters."
                : "PIN is too weak. Avoid common patterns like 1234 or repeated digits."
            isLoading = false
            // Clear PIN fields like in PINSetupViewModel
            pin = ""
            confirmPin = ""
            return false
        }

        Logger.security.info("Setting up poison pill PIN")
        let success: Bool = await self.createPoisonPillUseCase.createPin(pppin: pin, pinType: pinType)
        
        isLoading = false
        
        if success {
            Logger.security.info("Poison pill PIN setup completed successfully")
            return true
        } else {
            showError = true
            errorMessage = "Failed to setup poison pill PIN"
            // Clear PIN fields on failure like in PINSetupViewModel
            pin = ""
            confirmPin = ""
            Logger.security.error("Failed to setup poison pill PIN - createPinUseCase returned false")
            return false
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        currentStep = .explanation1
        pin = ""
        confirmPin = ""
        showError = false
        errorMessage = ""
        isLoading = false
    }
}

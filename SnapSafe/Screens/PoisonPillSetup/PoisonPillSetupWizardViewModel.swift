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
    case explanation = 0
    case pinCreation = 1
    
    var title: String {
        switch self {
        case .explanation:
            return "Poison Pill"
        case .pinCreation:
            return "Set Poison Pill PIN"
        }
    }
}

@MainActor
final class PoisonPillSetupWizardViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentStep: PoisonPillWizardStep = .explanation
    @Published var pin: String = ""
    @Published var confirmPin: String = ""
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    
    // MARK: - Dependencies
    
    @Injected(\.createPinUseCase)
    private var createPinUseCase: CreatePinUseCase
    
    @Injected(\.createPoisonPillUseCase)
    private var createPoisonPillUseCase: CreatePoisonPillUseCase
    
    // MARK: - Computed Properties
    
    var canProceedFromPinCreation: Bool {
        return pin.count == 4 && 
               confirmPin.count == 4 && 
               pin == confirmPin &&
               !isLoading
    }
    
    var progressValue: Double {
        Double(currentStep.rawValue + 1) / Double(PoisonPillWizardStep.allCases.count)
    }
    
    // MARK: - Navigation Methods
    
    func goToNextStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep == .explanation {
                currentStep = .pinCreation
            }
        }
    }
    
    func goToPreviousStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep == .pinCreation {
                currentStep = .explanation
            }
        }
    }
    
    // MARK: - PIN Management
    
    func updatePIN(_ newValue: String) {
        let filtered = String(newValue.prefix(4).filter { $0.isNumber })
        if pin != filtered {
            pin = filtered
            validatePINs()
        }
    }
    
    func updateConfirmPIN(_ newValue: String) {
        let filtered = String(newValue.prefix(4).filter { $0.isNumber })
        if confirmPin != filtered {
            confirmPin = filtered
            validatePINs()
        }
    }
    
    private func validatePINs() {
        showError = false
        
        if pin.count == 4 && confirmPin.count == 4 && pin != confirmPin {
            showError = true
            errorMessage = "PINs do not match"
        }
    }
    
    func setupPoisonPillPIN() async -> Bool {
        guard canProceedFromPinCreation else { return false }
        
        isLoading = true
        showError = false
        
        do {
            Logger.security.info("Setting up poison pill PIN")
            let success: Bool = await self.createPoisonPillUseCase.createPin(pppin: pin)
            
            if success {
                Logger.security.info("Poison pill PIN setup completed successfully")
                return true
            } else {
                showError = true
                errorMessage = "Failed to setup poison pill PIN"
                Logger.security.error("Failed to setup poison pill PIN - createPinUseCase returned false")
                return false
            }
        } catch {
            showError = true
            errorMessage = "An error occurred while setting up the PIN"
            Logger.security.error("Error setting up poison pill PIN", metadata: [
                "error": .string(String(describing: error))
            ])
            return false
        }
        
        isLoading = false
    }
    
    // MARK: - Reset
    
    func reset() {
        currentStep = .explanation
        pin = ""
        confirmPin = ""
        showError = false
        errorMessage = ""
        isLoading = false
    }
}

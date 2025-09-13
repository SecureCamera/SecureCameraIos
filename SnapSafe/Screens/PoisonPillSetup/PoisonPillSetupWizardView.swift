//
//  PoisonPillSetupWizardView.swift
//  SnapSafe
//
//  Created by Claude on 9/12/25.
//

import SwiftUI
import FactoryKit
import Logging

struct PoisonPillSetupWizardView: View {
    @StateObject private var viewModel = PoisonPillSetupWizardViewModel()
    @EnvironmentObject private var nav: AppNavigationState
    
    private func dismiss() {
        nav.navigateBack()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress Indicator
                progressHeader
                
                // Step Content
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
            .obscuredWhenInactive()
            .screenCaptureProtected()
        }
    }
    
    // MARK: - Progress Header
    
    @ViewBuilder
    private var progressHeader: some View {
        VStack(spacing: 15) {
            HStack {
                Button("Cancel") {
                    handleCancel()
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                Text(viewModel.currentStep.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if viewModel.currentStep == .pinCreation {
                    Button("Back") {
                        viewModel.goToPreviousStep()
                    }
                    .foregroundColor(.orange)
                } else {
                    // Invisible button for balance
                    Button("Back") {
                        viewModel.goToPreviousStep()
                    }
                    .opacity(0)
                    .disabled(true)
                }
            }
            .padding(.horizontal)
            
            // Progress Bar
            ProgressView(value: viewModel.progressValue)
                .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Step Content
    
    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .explanation:
            PoisonPillExplanationView(
                onNext: {
                    viewModel.goToNextStep()
                },
                onCancel: {
                    handleCancel()
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
            
        case .pinCreation:
            PoisonPillPinCreationView(
                pin: $viewModel.pin,
                confirmPin: $viewModel.confirmPin,
                showError: $viewModel.showError,
                errorMessage: $viewModel.errorMessage,
                isLoading: $viewModel.isLoading,
                canProceed: viewModel.canProceedFromPinCreation,
                onPinChange: viewModel.updatePIN,
                onConfirmPinChange: viewModel.updateConfirmPIN,
                onSetup: {
                    Task {
                        let success = await viewModel.setupPoisonPillPIN()
                        if success {
                            Logger.ui.info("Poison pill setup wizard completed successfully")
                            handleSuccess()
                        }
                    }
                },
                onCancel: {
                    handleCancel()
                }
            )
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleCancel() {
        Logger.ui.info("Poison pill setup wizard cancelled by user")
        viewModel.reset()
        dismiss()
    }
    
    private func handleSuccess() {
        Logger.ui.info("Poison pill setup completed, dismissing wizard")
        dismiss()
    }
}

#Preview("Step 1 - Explanation") {
    PoisonPillSetupWizardView()
}

#Preview("Step 2 - PIN Creation") {
    let view = PoisonPillSetupWizardView()
    
    //view.viewModel.currentStep = .pinCreation
}

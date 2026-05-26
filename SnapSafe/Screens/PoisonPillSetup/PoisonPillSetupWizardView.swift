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
                
                // Fixed bottom button (only show for explanation steps, not PIN creation)
                if viewModel.currentStep != .pinCreation {
                    VStack(spacing: 0) {
                        Divider()
                            .background(Color.gray.opacity(0.3))
                        
                        Button(action: {
                            viewModel.goToNextStep()
                        }) {
                            HStack {
                                Text(viewModel.currentStep == .explanation3 ? "Set Up PIN" : "Continue")
                                    .fontWeight(.medium)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.orange)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                    }
                    .background(Color(UIColor.systemBackground))
                }
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
                .foregroundColor(viewModel.isLoading ? .gray : .secondary)
                .disabled(viewModel.isLoading)
                
                Spacer()
                
                Text(viewModel.currentStep.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if viewModel.currentStep != .explanation1 {
                    Button("Back") {
                        viewModel.goToPreviousStep()
                    }
                    .foregroundColor(viewModel.isLoading ? .gray : .orange)
                    .disabled(viewModel.isLoading)
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
        case .explanation1:
            PoisonPillExplanationView(step: ExplanationStep.poisonPillSteps[0])
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
            
        case .explanation2:
            PoisonPillExplanationView(step: ExplanationStep.poisonPillSteps[1])
            .transition(.asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading)
            ))
            
        case .explanation3:
            PoisonPillExplanationView(step: ExplanationStep.poisonPillSteps[2])
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
                isPinLengthValid: viewModel.isPinLengthValid,
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
    PoisonPillSetupWizardView()
}

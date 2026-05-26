//
//  PINVerificationView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

struct PINVerificationView: View {
    @StateObject private var viewModel = PINVerificationViewModel()
    @FocusState private var isPINFieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.shield")
                .font(.system(size: 70))
                .foregroundColor(.blue)
                .padding(.top, 50)
                .accessibilityHidden(true)   // decorative — text labels provide context
            
            Text("SnapSafe")
                .foregroundColor(.primary)
                .font(.largeTitle)
                .bold()

            Text("Enter your PIN to continue")
                .foregroundColor(.secondary)
            
            if viewModel.shouldShowAttemptsWarning {
                Text(viewModel.attemptsWarningMessage)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.top, 5)
            }
            
            SecureField("PIN", text: $viewModel.pin, prompt: Text("PIN").foregroundColor(.secondary))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding()
                .foregroundColor(.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(UIColor.systemGray3), lineWidth: 1)
                )
                .padding(.horizontal, 50)
                .focused($isPINFieldFocused)
                .disabled(viewModel.isLoading)
                .onChange(of: viewModel.pin) { _, newValue in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.updatePIN(newValue)
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        isPINFieldFocused = false
                    }
                }
            
            if viewModel.showError {
                Text(viewModel.errorMessage)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.top, 5)
            }
            
            Button(action: {
                isPINFieldFocused = false
                viewModel.unlockButtonTapped()
            }) {
                HStack {
                    if viewModel.isLastAttempt {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                    }
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    Text(viewModel.unlockButtonText)
                        .foregroundColor(.white)
                }
                .padding()
                .frame(width: 200)
                .background(viewModel.unlockButtonBackgroundColor)
                .cornerRadius(10)
            }
            .disabled(viewModel.isUnlockButtonDisabled)
            .padding(.top, 20)
            .accessibilityLabel(viewModel.unlockButtonText)
            .accessibilityHint(viewModel.isLastAttempt ? "Warning: one attempt remaining before data wipe" : "")
            
            if viewModel.shouldShowAttemptsWarning {
                Text("10 failed attempts will result in a full data wipe.\nALL PHOTOS WILL BE LOST!")
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.top, 5)
                    .accessibilityLabel("Warning: 10 failed attempts will result in a full data wipe. All photos will be lost.")
            }
            
            Spacer()
        }
        .onAppear {
            viewModel.onAppear()
            isPINFieldFocused = true
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Clear PIN content and dismiss keyboard when app goes to background or inactive
            if newPhase == .background || newPhase == .inactive {
                isPINFieldFocused = false
                viewModel.clearPinContent()
            }
        }
        .onChange(of: viewModel.showError) { _, showError in
            if showError {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        .obscuredWhenInactive()
        .screenCaptureProtected()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isPINFieldFocused = false
                }
            }
        }
    }
}

#Preview {
    PINVerificationView()
}

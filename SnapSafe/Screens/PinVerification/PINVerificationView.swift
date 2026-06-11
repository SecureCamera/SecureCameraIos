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

    // Reveal the action once the user has started entering a PIN (or while a
    // verification is in flight) — avoids an idle, disabled button at rest.
    private var showUnlockButton: Bool {
        !viewModel.pin.isEmpty || viewModel.isLoading
    }

    private var unlockButton: some View {
        Button(action: {
            isPINFieldFocused = false
            viewModel.unlockButtonTapped()
        }) {
            HStack {
                if viewModel.isLastAttempt {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.white)
                }
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundStyle(.white)
                }
                Text(viewModel.unlockButtonText)
                    .foregroundStyle(.white)
            }
            .padding()
            .frame(width: 200)
            .background(viewModel.unlockButtonBackgroundColor)
            .clipShape(.rect(cornerRadius: 10))
        }
        .disabled(viewModel.isUnlockButtonDisabled)
        .accessibilityLabel(viewModel.unlockButtonText)
        .accessibilityHint(viewModel.isLastAttempt ? "Warning: one attempt remaining before data wipe" : "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // The icon slides up out of view once the field is focused,
                // freeing vertical room so the button sits just above the
                // keypad (mirrors the poison-pill PIN entry screen).
                if !isPINFieldFocused {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 70))
                        .foregroundStyle(.blue)
                        .padding(.top, 50)
                        .accessibilityHidden(true)   // decorative — text labels provide context
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Text("SnapSafe")
                    .foregroundStyle(.primary)
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, isPINFieldFocused ? 24 : 0)

                Text("Enter your PIN to continue")
                    .foregroundStyle(.secondary)

                if viewModel.shouldShowAttemptsWarning {
                    Text(viewModel.attemptsWarningMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.top, 5)
                }

                SecureField("PIN", text: $viewModel.pin, prompt: Text("PIN").foregroundStyle(.secondary))
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .padding()
                    .foregroundStyle(.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(UIColor.systemGray3), lineWidth: 1)
                    )
                    .padding(.horizontal, 50)
                    .focused($isPINFieldFocused)
                    .disabled(viewModel.isLoading)
                    .onChange(of: viewModel.pin) { _, newValue in
                        viewModel.updatePIN(newValue)
                    }
                    .onChange(of: viewModel.isLoading) { _, isLoading in
                        if isLoading {
                            isPINFieldFocused = false
                        }
                    }

                if viewModel.showError {
                    Text(viewModel.errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.top, 5)
                }

                if viewModel.showRetryableError {
                    Text(viewModel.retryableErrorMessage)
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .padding(.top, 5)
                }

                if viewModel.shouldShowAttemptsWarning {
                    Text("10 failed attempts will result in a full data wipe.\nALL PHOTOS WILL BE LOST!")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.top, 5)
                        .accessibilityLabel("Warning: 10 failed attempts will result in a full data wipe. All photos will be lost.")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if showUnlockButton {
                unlockButton
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: showUnlockButton)
        .animation(.snappy, value: isPINFieldFocused)
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
        .onChange(of: viewModel.showError) { _, showError in }
        .obscuredWhenInactive()
        .screenCaptureProtected()
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.pin)
        .sensoryFeedback(.error, trigger: viewModel.showError) { _, new in new }
    }
}

#Preview {
    PINVerificationView()
}

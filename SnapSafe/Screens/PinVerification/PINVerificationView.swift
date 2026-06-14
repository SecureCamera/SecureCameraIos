//
//  PINVerificationView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

struct PINVerificationView: View {
    @StateObject private var viewModel = PINVerificationViewModel()
    @Environment(\.scenePhase) private var scenePhase

    private var showUnlockButton: Bool {
        !viewModel.pin.isEmpty || viewModel.isLoading
    }

    private var shouldFocusField: Bool {
        scenePhase == .active && !viewModel.isLoading
    }

    private var unlockButton: some View {
        Button(action: viewModel.unlockButtonTapped) {
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
            VStack(spacing: 24) {
                Text("SnapSafe")
                    .foregroundStyle(.primary)
                    .font(.largeTitle)
                    .bold()
                    .padding(.top, 32)

                Text("Enter your PIN to continue")
                    .foregroundStyle(.secondary)

                if viewModel.shouldShowAttemptsWarning {
                    Text(viewModel.attemptsWarningMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                PINEntryField(
                    text: $viewModel.pin,
                    maxLength: MAX_PIN_LENGTH,
                    isEnabled: !viewModel.isLoading,
                    shouldFocus: shouldFocusField
                )
                .frame(height: 52)
                .padding(.horizontal, 50)
                .onChange(of: viewModel.pin) { _, newValue in
                    viewModel.updatePIN(newValue)
                }

                if viewModel.showError {
                    Text(viewModel.errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                if viewModel.showRetryableError {
                    Text(viewModel.retryableErrorMessage)
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if viewModel.shouldShowAttemptsWarning {
                    Text("10 failed attempts will result in a full data wipe.\nALL PHOTOS WILL BE LOST!")
                        .foregroundStyle(.red)
                        .font(.callout)
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
        .task {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                viewModel.clearPinContent()
            }
        }
        .obscuredWhenInactive()
        .screenCaptureProtected()
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.pin)
        .sensoryFeedback(.error, trigger: viewModel.showError) { _, new in new }
    }
}

#Preview {
    PINVerificationView()
}

//
//  PINSetupView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI
import FactoryKit
import Logging

struct PINSetupView: View {
    @StateObject private var viewModel = PINSetupViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var revealPin = false
    @State private var revealConfirmPin = false

    // Cache computed values to reduce view updates
    private var buttonDisabled: Bool {
        !viewModel.canSubmit
    }
    
    private var buttonBackgroundColor: Color {
        viewModel.canSubmit ? Color.blue : Color.gray
    }

    // Reveal the action once the user has started entering a PIN (or while the
    // PIN is being set) — avoids an idle, disabled button at rest.
    private var showSetPinButton: Bool {
        !viewModel.pin.isEmpty || !viewModel.confirmPin.isEmpty || viewModel.isLoading
    }

    private var setPinButton: some View {
        Button(action: {
            Task {
                let success = await viewModel.createPin()
                if success {
                    Logger.ui.info("PIN setup complete, marking intro as completed")
                }
            }
        }) {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundStyle(.white)
                }
                Text(viewModel.isLoading ? "Setting PIN..." : "Set PIN")
                    .foregroundStyle(.white)
            }
            .padding()
            .frame(minWidth: 200, maxWidth: 300)
            .background(buttonBackgroundColor)
            .clipShape(.rect(cornerRadius: 10))
        }
        .disabled(buttonDisabled)
    }

    var body: some View {
        ScrollView {
                VStack(spacing: 30) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 70))
                        .foregroundStyle(.blue)
                        .padding(.top, 50)
                        .accessibilityHidden(true)
                    
                    Text("Set Up Security PIN")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("Please create a PIN to secure your photos")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    VStack(spacing: 20) {
                        Toggle(isOn: Binding(
                            get: { viewModel.isAlphanumeric },
                            set: { viewModel.setAlphanumeric($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use Alphanumeric PIN")
                                    .font(.subheadline)
                                Text("Letters and numbers allowed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))
                        .disabled(!viewModel.pin.isEmpty || !viewModel.confirmPin.isEmpty)

                        pinField(
                            placeholder: "Enter PIN",
                            text: $viewModel.pin,
                            reveal: $revealPin
                        )

                        if !viewModel.pin.isEmpty && viewModel.pin.count < 6 {
                            Text(PINStrings.shortPinWarning)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))
                                .transition(.opacity)
                        }

                        pinField(
                            placeholder: "Confirm PIN",
                            text: $viewModel.confirmPin,
                            reveal: $revealConfirmPin
                        )
                    }
                    .animation(.snappy, value: !viewModel.pin.isEmpty && viewModel.pin.count < 6)

                    if viewModel.showError {
                        Text(viewModel.errorMessage)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .padding(.top, 5)
                    }
                    
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Choose a different PIN than the one used to unlock this device!")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
                    
                }
            }
            .safeAreaInset(edge: .bottom) {
                if showSetPinButton {
                    setPinButton
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showSetPinButton)
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
            .obscuredWhenInactive()
            .screenCaptureProtected()
            .task {
                await viewModel.loadAlphanumericSetting()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Clear PIN content and dismiss keyboard when app goes to background or inactive
                if newPhase == .background || newPhase == .inactive {
                    viewModel.clearPinContent()
                }
            }
    }

    private func pinField(
        placeholder: String,
        text: Binding<String>,
        reveal: Binding<Bool>
    ) -> some View {
        HStack(spacing: 0) {
            // Keeps the secure dots visually centered by balancing the trailing eye button.
            Image(systemName: "eye")
                .opacity(0)
                .padding(.leading, 12)
                .accessibilityHidden(true)

            RevealableSecureField(
                text: text,
                placeholder: placeholder,
                isAlphanumeric: viewModel.isAlphanumeric,
                maxLength: MAX_PIN_LENGTH,
                isSecure: !reveal.wrappedValue,
                isEnabled: true
            )

            Button {
                reveal.wrappedValue.toggle()
            } label: {
                Image(systemName: reveal.wrappedValue ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(reveal.wrappedValue ? "Hide PIN" : "Show PIN")
        }
        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
        .padding(.horizontal, min(50, UIScreen.main.bounds.width * 0.1))
    }
}

#Preview {
    PINSetupView()
}

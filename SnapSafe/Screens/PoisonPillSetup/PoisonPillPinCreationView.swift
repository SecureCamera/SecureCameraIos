//
//  PoisonPillPinCreationView.swift
//  SnapSafe
//
//  Created by Claude on 9/12/25.
//

import SwiftUI

struct PoisonPillPinCreationView: View {
    @Binding var pin: String
    @Binding var confirmPin: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isLoading: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var pinFocused = false
    @State private var confirmFocused = false
    @State private var revealPin = false
    @State private var revealConfirmPin = false

    // True while the user is actively entering a PIN (a field is focused).
    private var isEntering: Bool { pinFocused || confirmFocused }

    let isAlphanumeric: Bool
    let canProceed: Bool
    let onPinChange: (String) -> Void
    let onConfirmPinChange: (String) -> Void
    let onSetup: () -> Void
    let isPinLengthValid: (Int) -> Bool

    // Reveal the action once the user has started entering a PIN (or while
    // setup is in flight) — avoids an idle, disabled button at rest. The
    // destructive action stays an explicit tap; it is never auto-submitted.
    private var showSetupButton: Bool {
        !pin.isEmpty || !confirmPin.isEmpty || isLoading
    }

    private var setupButton: some View {
        Button(action: {
            hideKeyboard()
            onSetup()
        }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .foregroundStyle(.white)
                }
                Text(isLoading ? "Setting up..." : "Setup Poison Pill")
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canProceed ? Color.orange : Color.gray)
            .clipShape(.rect(cornerRadius: 10))
        }
        .disabled(!canProceed)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                // Header Icon — slides up out of view once the user focuses a
                // field, freeing vertical room for the fields, button, and keypad.
                if !isEntering {
                    Image(systemName: "lock.trianglebadge.exclamationmark")
                        .font(.system(size: 70))
                        .foregroundStyle(.orange)
                        .padding(.top, max(30, geometry.safeAreaInsets.top + 20))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

            // Title
            Text("Set Poison Pill PIN")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Subtitle
            Text("Create a PIN that will trigger emergency deletion")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // PIN Input Fields
            VStack(spacing: 20) {
                pinField(
                    placeholder: "Enter new PIN",
                    text: $pin,
                    reveal: $revealPin,
                    focused: $pinFocused,
                    isValid: isPinLengthValid(pin.count),
                    onChange: onPinChange
                )

                if !pin.isEmpty && pin.count < 6 {
                    Text(PINStrings.shortPinWarning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 50)
                        .transition(.opacity)
                }

                pinField(
                    placeholder: "Confirm PIN",
                    text: $confirmPin,
                    reveal: $revealConfirmPin,
                    focused: $confirmFocused,
                    isValid: isPinLengthValid(confirmPin.count),
                    onChange: onConfirmPinChange
                )
            }
            .animation(.snappy, value: !pin.isEmpty && pin.count < 6)

            // Error Message
            if showError {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .padding(.top, 5)
            }
            
            // Warning
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text("When entered, this PIN it will immediately and permanently delete all photos and encryption keys.")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                if showSetupButton {
                    setupButton
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: showSetupButton)
            .animation(.snappy, value: isEntering)
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.container, edges: [])
        .onTapGesture {
            hideKeyboard()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Clear PIN content and dismiss keyboard when app goes to background or inactive
            if newPhase == .background || newPhase == .inactive {
                hideKeyboard()
                pin = ""
                confirmPin = ""
                showError = false
            }
        }
    }

    private func pinField(
        placeholder: String,
        text: Binding<String>,
        reveal: Binding<Bool>,
        focused: Binding<Bool>,
        isValid: Bool,
        onChange: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 0) {
            // Keeps the secure dots visually centered by balancing the trailing eye button.
            Image(systemName: "eye")
                .opacity(0)
                .padding(.leading, 12)
                .accessibilityHidden(true)

            RevealableSecureField(
                text: text,
                isFocused: focused,
                placeholder: placeholder,
                isAlphanumeric: isAlphanumeric,
                maxLength: MAX_PIN_LENGTH,
                isSecure: !reveal.wrappedValue,
                isEnabled: !isLoading
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
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isValid ? Color.orange : Color.gray, lineWidth: 1)
        )
        .padding(.horizontal, 50)
        .disabled(isLoading)
        .opacity(isLoading ? 0.6 : 1.0)
        .onChange(of: text.wrappedValue) { _, newValue in
            onChange(newValue)
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

#Preview {
    @Previewable @State var pin = ""
    @Previewable @State var confirmPin = ""
    @Previewable @State var showError = false
    @Previewable @State var errorMessage = ""
    @Previewable @State var isLoading = false

    return NavigationStack {
        PoisonPillPinCreationView(
            pin: $pin,
            confirmPin: $confirmPin,
            showError: $showError,
            errorMessage: $errorMessage,
            isLoading: $isLoading,
            isAlphanumeric: false,
            canProceed: false,
            onPinChange: { _ in },
            onConfirmPinChange: { _ in },
            onSetup: {},
            isPinLengthValid: { length in length >= 4 && length <= 10 }
        )
    }
}

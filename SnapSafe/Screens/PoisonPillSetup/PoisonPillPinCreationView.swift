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
    
    let canProceed: Bool
    let onPinChange: (String) -> Void
    let onConfirmPinChange: (String) -> Void
    let onSetup: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
            // Header Icon
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 70))
                .foregroundColor(.orange)
                .padding(.top, 50)
            
            // Title
            Text("Set Poison Pill PIN")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Subtitle
            Text("Create a 4-digit PIN that will trigger emergency deletion")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // PIN Input Fields
            VStack(spacing: 20) {
                SecureField("Enter 4-digit PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(pin.count == 4 ? Color.orange : Color.gray, lineWidth: 1)
                    )
                    .padding(.horizontal, 50)
                    .onChange(of: pin) { _, newValue in
                        onPinChange(newValue)
                    }
                
                SecureField("Confirm PIN", text: $confirmPin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(confirmPin.count == 4 ? Color.orange : Color.gray, lineWidth: 1)
                    )
                    .padding(.horizontal, 50)
                    .onChange(of: confirmPin) { _, newValue in
                        onConfirmPinChange(newValue)
                    }
            }
            
            // Error Message
            if showError {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.top, 5)
            }
            
            // PIN Requirements
            if pin.isEmpty && confirmPin.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    requirementRow(text: "Must be exactly 4 digits", isValid: pin.count == 4)
                    requirementRow(text: "Both PINs must match", isValid: pin == confirmPin && !pin.isEmpty)
                    requirementRow(text: "Should be different from your main PIN", isValid: true)
                }
                .padding(.horizontal, 40)
            }
            
            // Warning
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Warning: This will permanently delete all your data")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
                
                Text("Remember this PIN carefully. When entered, it will immediately and permanently delete all photos and encryption keys.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
            
            // Action Buttons
            VStack(spacing: 15) {
                Button(action: onSetup) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        Text(isLoading ? "Setting up..." : "Setup Poison Pill")
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed ? Color.orange : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(!canProceed)
                
                Button("Cancel", action: onCancel)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
        }
        .navigationBarHidden(true)
        .onTapGesture {
            hideKeyboard()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    hideKeyboard()
                }
            }
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    @ViewBuilder
    private func requirementRow(text: String, isValid: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isValid ? .green : .gray)
                .font(.caption)
            
            Text(text)
                .font(.caption)
                .foregroundColor(isValid ? .primary : .secondary)
            
            Spacer()
        }
    }
}

#Preview {
    @State var pin = ""
    @State var confirmPin = ""
    @State var showError = false
    @State var errorMessage = ""
    @State var isLoading = false
    
    return NavigationView {
        PoisonPillPinCreationView(
            pin: $pin,
            confirmPin: $confirmPin,
            showError: $showError,
            errorMessage: $errorMessage,
            isLoading: $isLoading,
            canProceed: false,
            onPinChange: { _ in },
            onConfirmPinChange: { _ in },
            onSetup: {},
            onCancel: {}
        )
    }
}
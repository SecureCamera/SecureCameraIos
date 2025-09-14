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
    let isPinLengthValid: (Int) -> Bool
    let onCancel: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 30) {
                // Header Icon
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .font(.system(size: 70))
                    .foregroundColor(.orange)
                    .padding(.top, max(30, geometry.safeAreaInsets.top + 20))
            
            // Title
            Text("Set Poison Pill PIN")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Subtitle
            Text("Create a PIN that will trigger emergency deletion")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // PIN Input Fields
            VStack(spacing: 20) {
                SecureField("Enter new PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isPinLengthValid(pin.count) ? Color.orange : Color.gray, lineWidth: 1)
                    )
                    .padding(.horizontal, 50)
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.6 : 1.0)
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
                            .stroke(isPinLengthValid(confirmPin.count) ? Color.orange : Color.gray, lineWidth: 1)
                    )
                    .padding(.horizontal, 50)
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.6 : 1.0)
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
            
            // Warning
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text("When entered, this PIN it will immediately and permanently delete all photos and encryption keys.")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 30)
            
            // Action Buttons
            VStack(spacing: 15) {
                Button(action: {
                    hideKeyboard()
                    onSetup()
                }) {
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
            }
            .padding(.horizontal, 40)
            .padding(.bottom, max(30, geometry.safeAreaInsets.bottom + 20))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea(.container, edges: [])
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
}

#Preview {
    @Previewable @State var pin = ""
    @Previewable @State var confirmPin = ""
    @Previewable @State var showError = false
    @Previewable @State var errorMessage = ""
    @Previewable @State var isLoading = false
    
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
            isPinLengthValid: { length in length >= 4 && length <= 10 },
            onCancel: {}
        )
    }
}

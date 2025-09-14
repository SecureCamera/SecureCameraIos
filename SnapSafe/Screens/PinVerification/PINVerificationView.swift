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
    
    // Cache computed values to reduce view updates
    private var buttonDisabled: Bool {
        viewModel.pin.count != 4 || viewModel.isLoading
    }
    
    private var buttonBackgroundColor: Color {
        viewModel.pin.count == 4 && !viewModel.isLoading ? Color.blue : Color.gray
    }
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "lock.shield")
                .font(.system(size: 70))
                .foregroundColor(.blue)
                .padding(.top, 50)
            
            Text("SnapSafe")
                .font(.largeTitle)
                .bold()
            
            Text("Enter your PIN to continue")
                .foregroundColor(Color(UIColor.lightText))
            
            SecureField("PIN", text: $viewModel.pin, prompt: Text("PIN").foregroundColor(Color(UIColor.lightText)))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding()
                .foregroundColor(Color(UIColor.lightText))
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
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.top, 5)
            }
            
            Button(action: {
                isPINFieldFocused = false
                viewModel.unlockButtonTapped()
            }) {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    Text(viewModel.isLoading ? "Verifying..." : "Unlock")
                        .foregroundColor(.white)
                }
                .padding()
                .frame(width: 200)
                .background(buttonBackgroundColor)
                .cornerRadius(10)
            }
            .disabled(buttonDisabled)
            .padding(.top, 20)
            
            Spacer()
        }
        .onAppear {
            viewModel.onAppear()
            isPINFieldFocused = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Dismiss keyboard when app goes to background or inactive
            if newPhase == .background || newPhase == .inactive {
                isPINFieldFocused = false
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

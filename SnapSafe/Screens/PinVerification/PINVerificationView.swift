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
            
            Text("SnapSafe")
                .font(.largeTitle)
                .bold()
            
            Text("Enter your PIN to continue")
                .foregroundColor(.secondary)
            
            SecureField("PIN", text: $viewModel.pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).stroke(viewModel.isLoading ? Color.gray.opacity(0.5) : Color.gray, lineWidth: 1))
                .padding(.horizontal, 50)
                .focused($isPINFieldFocused)
                .disabled(viewModel.isLoading)
                .opacity(viewModel.isLoading ? 0.6 : 1.0)
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
                .background(viewModel.unlockButtonBackgroundColor)
                .cornerRadius(10)
            }
            .disabled(viewModel.isUnlockButtonDisabled)
            .padding(.top, 20)
            
            Spacer()
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Dismiss keyboard when app goes to background or inactive
            if newPhase == .background || newPhase == .inactive {
                isPINFieldFocused = false
            }
        }
        .obscuredWhenInactive()
        .screenCaptureProtected()
    }
}

#Preview {
    PINVerificationView()
}
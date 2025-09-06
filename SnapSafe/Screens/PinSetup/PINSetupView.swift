//
//  PINSetupView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI
import FactoryKit

struct PINSetupView: View {
    @StateObject private var viewModel = PINSetupViewModel()
    @Binding var isPINSetupComplete: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 70))
                    .foregroundColor(.blue)
                    .padding(.top, 50)
                
                Text("Set Up Security PIN")
                    .font(.largeTitle)
                    .bold()
                
                Text("Please create a 4-digit PIN to secure your photos")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 20) {
                    SecureField("Enter 4-digit PIN", text: $viewModel.pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                        .padding(.horizontal, 50)
                        .onChange(of: viewModel.pin) { _, newValue in
                            viewModel.updatePIN(newValue)
                        }
                    
                    SecureField("Confirm PIN", text: $viewModel.confirmPin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                        .padding(.horizontal, 50)
                        .onChange(of: viewModel.confirmPin) { _, newValue in
                            viewModel.updateConfirmPIN(newValue)
                        }
                }
                
                if viewModel.showError {
                    Text(viewModel.errorMessage)
                        .foregroundColor(.red)
                        .font(.callout)
                        .padding(.top, 5)
                }
                
                Button(action: {
                    Task {
                        let success = await viewModel.createPin()
                        await MainActor.run {
                            if success {
                                isPINSetupComplete = true
                            }
                        }
                    }
                }) {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        Text(viewModel.isLoading ? "Setting PIN..." : "Set PIN")
                            .foregroundColor(.white)
                    }
                    .padding()
                    .frame(width: 200)
                    .background(
                        viewModel.canSubmit ? Color.blue : Color.gray
                    )
                    .cornerRadius(10)
                }
                .disabled(!viewModel.canSubmit)
                .padding(.top, 20)
                
                Spacer()
                
                Text("Your PIN will be required when opening the app and when it returns from background.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
            .obscuredWhenInactive()
            .screenCaptureProtected()
        }
    }
}

#Preview {
    PINSetupView(isPINSetupComplete: .constant(false))
}

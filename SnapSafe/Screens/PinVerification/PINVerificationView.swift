//
//  PINVerificationView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

struct PINVerificationView: View {
    @StateObject private var viewModel = PINVerificationViewModel()
    
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
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                .padding(.horizontal, 50)
                .onChange(of: viewModel.pin) { _, newValue in
                    viewModel.updatePIN(newValue)
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
                Text("Unlock")
                    .foregroundColor(.white)
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
        .obscuredWhenInactive()
        .screenCaptureProtected()
    }
}

#Preview {
    PINVerificationView()
}
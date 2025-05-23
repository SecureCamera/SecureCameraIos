//
//  PINVerificationView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

struct PINVerificationView: View {
    @ObservedObject private var pinManager = PINManager.shared
    @State private var pin = ""
    @State private var showError = false
    @State private var attempts = 0
    @Binding var isAuthenticated: Bool
    
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
            
            SecureField("PIN", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                .padding(.horizontal, 50)
                .onChange(of: pin) { _, newValue in
                    // Limit to 4 digits
                    if newValue.count > 4 {
                        pin = String(newValue.prefix(4))
                    }
                    
                    // Only allow numbers
                    if !newValue.allSatisfy({ $0.isNumber }) {
                        pin = newValue.filter { $0.isNumber }
                    }
                    
                    // Auto-verify when 4 digits are entered
                    if newValue.count == 4 {
                        verifyPIN()
                    }
                }
            
            if showError {
                Text("Invalid PIN. Please try again.")
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding(.top, 5)
            }
            
            Button(action: {
                verifyPIN()
            }) {
                Text("Unlock")
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 200)
                    .background(pin.count == 4 ? Color.blue : Color.gray)
                    .cornerRadius(10)
            }
            .disabled(pin.count != 4)
            .padding(.top, 20)
            
            Spacer()
        }
        .onAppear {
            // Update last active time when view appears
            pinManager.updateLastActiveTime()
        }
    }
    
    private func verifyPIN() {
        if pinManager.verifyPIN(pin) {
            // PIN is correct
            isAuthenticated = true
            showError = false
            
            // Update last active time
            pinManager.updateLastActiveTime()
        } else {
            // PIN is incorrect
            isAuthenticated = false
            showError = true
            attempts += 1
            pin = ""
            
            // Could add more sophisticated security measures here, like
            // temporary lockout after multiple failed attempts
        }
    }
}

#Preview {
    PINVerificationView(isAuthenticated: .constant(false))
}
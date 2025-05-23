//
//  PINSetupView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/22/25.
//

import SwiftUI

struct PINSetupView: View {
    @ObservedObject private var pinManager = PINManager.shared
    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var showError = false
    @State private var errorMessage = ""
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
                    SecureField("Enter 4-digit PIN", text: $pin)
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
                        }
                    
                    SecureField("Confirm PIN", text: $confirmPin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                        .padding(.horizontal, 50)
                        .onChange(of: confirmPin) { _, newValue in
                            // Limit to 4 digits
                            if newValue.count > 4 {
                                confirmPin = String(newValue.prefix(4))
                            }
                            
                            // Only allow numbers
                            if !newValue.allSatisfy({ $0.isNumber }) {
                                confirmPin = newValue.filter { $0.isNumber }
                            }
                        }
                }
                
                if showError {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.callout)
                        .padding(.top, 5)
                }
                
                Button(action: {
                    savePIN()
                }) {
                    Text("Set PIN")
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 200)
                        .background(
                            (pin.count == 4 && confirmPin.count == 4) ? 
                                Color.blue : Color.gray
                        )
                        .cornerRadius(10)
                }
                .disabled(pin.count != 4 || confirmPin.count != 4)
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
        }
    }
    
    private func savePIN() {
        // Validate PIN
        if pin.count != 4 {
            showError = true
            errorMessage = "PIN must be 4 digits"
            return
        }
        
        // Check if PINs match
        if pin != confirmPin {
            showError = true
            errorMessage = "PINs do not match"
            return
        }
        
        // Save PIN
        pinManager.setPIN(pin)
        
        // Signal completion
        isPINSetupComplete = true
    }
}

#Preview {
    PINSetupView(isPINSetupComplete: .constant(false))
}
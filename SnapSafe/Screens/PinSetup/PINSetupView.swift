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
    @FocusState private var isPINFieldFocused: Bool
    @FocusState private var isConfirmPINFieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    @Injected(\.settingsDataSource)
    private var settings: SettingsDataSource
    
    // Cache computed values to reduce view updates
    private var buttonDisabled: Bool {
        !viewModel.canSubmit
    }
    
    private var buttonBackgroundColor: Color {
        viewModel.canSubmit ? Color.blue : Color.gray
    }
    
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
                
                Text("Please create a PIN to secure your photos")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 20) {
                    SecureField("Enter PIN", text: $viewModel.pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray, lineWidth: 1))
                        .padding(.horizontal, 50)
                        .focused($isPINFieldFocused)
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
                        .focused($isConfirmPINFieldFocused)
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
                
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Choose a different PIN than the one used to unlock this device!")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
                
                Button(action: {
                    isPINFieldFocused = false
                    isConfirmPINFieldFocused = false
                    Task {
                        let success = await viewModel.createPin()
                        if success {
                            Logger.ui.info("PIN setup complete, marking intro as completed")
                            await settings.setIntroCompleted(true)
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
                    .background(buttonBackgroundColor)
                    .cornerRadius(10)
                }
                .disabled(buttonDisabled)
                .padding(.top, 20)
                
                Spacer()
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
            .obscuredWhenInactive()
            .screenCaptureProtected()
            .onAppear {
                isPINFieldFocused = true
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Clear PIN content and dismiss keyboard when app goes to background or inactive
                if newPhase == .background || newPhase == .inactive {
                    isPINFieldFocused = false
                    isConfirmPINFieldFocused = false
                    viewModel.clearPinContent()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isPINFieldFocused = false
                        isConfirmPINFieldFocused = false
                    }
                }
            }
        }
    }
}

#Preview {
    PINSetupView()
}

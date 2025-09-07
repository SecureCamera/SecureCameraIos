//
//  SettingsView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import Combine
import CoreLocation
import SwiftUI

@_exported import Foundation

struct SettingsView: View {
    // Appearance setting
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    // ViewModel
    @StateObject private var viewModel = SettingsViewModel()
    
    // Location Manager (still needed for authorization status)
    @StateObject private var locationManager = LocationManager.shared
    
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationView {
            List {

                
                // SHARING SECTION
                Section(header: Text("Sharing Options")) {
                    Toggle("Sanitize File Name", isOn: $viewModel.sanitizeFileName)
                        .onChange(of: viewModel.sanitizeFileName) { _, newValue in
                            viewModel.updateSanitizeFileName(newValue)
                        }

                    Toggle("Sanitize Metadata", isOn: $viewModel.sanitizeMetadata)
                        .onChange(of: viewModel.sanitizeMetadata) { _, newValue in
                            viewModel.updateSanitizeMetadata(newValue)
                        }

                    Text("When enabled, personal information will be removed from photos before sharing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // PRIVACY & DETECTION SECTION
                Section(header: Text("Privacy & Detection")) {
                    Toggle("Face Detection", isOn: $viewModel.showFaceDetection)
                        .onChange(of: viewModel.showFaceDetection) { _, newValue in
                            viewModel.updateFaceDetection(newValue)
                        }

                    Text("When enabled, faces can be detected in photos for privacy protection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // LOCATION SECTION
                Section(header: Text("Location")) {
                    Toggle("Include Location Data", isOn: $viewModel.includeLocationData)
                        .onChange(of: viewModel.includeLocationData) { _, newValue in
                            viewModel.updateIncludeLocationData(newValue)
                        }

                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(locationManager.getAuthorizationStatusString())
                            .foregroundColor(viewModel.locationStatusColor)
                    }
                    
                    Button {
                        viewModel.requestLocationPermission()
                        } label: {
                            Text(viewModel.locationPermissionButtonText)
                        }

                    Text("When enabled, location data will be embedded in newly captured photos. Location requires permission and GPS availability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                // APPEARANCE SECTION
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Text("Choose how the app appears. System follows your device's appearance setting.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // DECOY PHOTOS SECTION
                Section(header: Text("Decoy Photos")) {
                    Button("Mark Decoys") {
                        viewModel.startSelectingDecoys()
                    }

                    Text("Decoy photos will be shown when emergency PIN is entered")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // SECURITY SECTION
                Section(header: Text("Security")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text("Secure")
                            .foregroundColor(.green)
                    }

                    Picker("Session Timeout", selection: $viewModel.sessionTimeout) {
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("Never").tag(0)
                    }
                    .onChange(of: viewModel.sessionTimeout) { _, newValue in
                        viewModel.updateSessionTimeout(newValue)
                    }
                }

                // APP PIN SECTION
                // TODO: changing your PIN ammounts to key rotation, which is not implemented yet
//                Section(header: Text("App PIN"), footer: Text("Enter a new 4-digit PIN twice to change your app security PIN")) {
//                    SecureField("New PIN (4 digits)", text: $viewModel.appPIN)
//                        .keyboardType(.numberPad)
//                        .autocorrectionDisabled(true)
//                        .textContentType(.oneTimeCode) // Prevents keychain suggestions
//                        .onChange(of: viewModel.appPIN) { _, newValue in
//                            viewModel.updateAppPIN(newValue)
//                        }
//                    
//                    SecureField("Confirm New PIN", text: $viewModel.confirmAppPIN)
//                        .keyboardType(.numberPad)
//                        .autocorrectionDisabled(true)
//                        .textContentType(.oneTimeCode)
//                        .onChange(of: viewModel.confirmAppPIN) { _, newValue in
//                            viewModel.updateConfirmAppPIN(newValue)
//                        }
//                    
//                    if viewModel.showPINError {
//                        Text(viewModel.pinErrorMessage)
//                            .foregroundColor(.red)
//                            .font(.caption)
//                            .padding(.vertical, 5)
//                    }
//                    
//                    if viewModel.showPINSuccess {
//                        Text("PIN updated successfully!")
//                            .foregroundColor(.green)
//                            .font(.caption)
//                            .padding(.vertical, 5)
//                    }
//
//                    Button("Update PIN") {
//                        viewModel.resetAppPIN()
//                    }
//                    .disabled(viewModel.isUpdatePINButtonDisabled)
//                }

                // EMERGENCY ERASURE SECTION (POISON PILL)
                Section(header: Text("Emergency Erasure"), footer: Text("If this PIN is entered, all photos will be immediately deleted")) {
                    SecureField("Set Emergency PIN", text: $viewModel.poisonPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode) // Prevents keychain suggestions

                    Button("Save Emergency PIN") {
                        viewModel.saveEmergencyPIN()
                    }
                    .foregroundColor(.red)
                    .disabled(viewModel.isSaveEmergencyPINDisabled)
                }

                // SECURITY RESET SECTION
                Section {
                    Button("Reset All Security Settings") {
                        viewModel.showSecurityResetConfirmation()
                    }
                    .foregroundColor(.red)

                } footer: {
                    Text("Resets all security settings to default values. Does not delete photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(appearanceMode.colorScheme)
            .onAppear {
                viewModel.onAppear()
            }
            .onChange(of: viewModel.shouldOpenSettings) { _, shouldOpen in
                if shouldOpen {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                    viewModel.shouldOpenSettings = false
                }
            }
            .alert(isPresented: $viewModel.showResetConfirmation) {
                Alert(
                    title: Text("Reset Security Settings"),
                    message: Text("Are you sure you want to reset all security settings to default? This action cannot be undone."),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.resetSecuritySettings()
                    },
                    secondaryButton: .cancel()
                )
            }
            .fullScreenCover(isPresented: $viewModel.isSelectingDecoys) {
                // Reset the selection flag when the sheet is dismissed
                viewModel.stopSelectingDecoys()
            } content: {
                NavigationView {
                    // Initialize SecureGalleryView in decoy selection mode
                    SecureGalleryView(selectingDecoys: true, onDismiss: {
                        viewModel.stopSelectingDecoys()
                    })
                }
            }
        }
    }
}

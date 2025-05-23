//
//  SettingsView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import Combine
import CoreLocation
import SwiftUI

// Add PINManager
@_exported import Foundation

struct SettingsView: View {
    // Sharing options
    @State private var sanitizeFileName = true
    @State private var sanitizeMetadata = true

    // Privacy and detection options
    @AppStorage("showFaceDetection") private var showFaceDetection = true

    // Security settings
    @State private var biometricEnabled = false
    @State private var sessionTimeout = 5 // minutes
    @State private var appPIN = ""
    @State private var confirmAppPIN = ""
    @State private var poisonPIN = ""
    @State private var showResetConfirmation = false
    @State private var requirePINOnResume: Bool = false
    @State private var showPINError = false
    @State private var pinErrorMessage = ""
    @State private var showPINSuccess = false

    // Decoy photos
    @State private var isSelectingDecoys = false

    // Location permissions
    @State private var locationPermissionStatus = "Not Determined"
    @StateObject private var locationManager = LocationManager.shared
    @State private var includeLocationData = false
    
    // PIN Manager
    @ObservedObject private var pinManager = PINManager.shared
    
    @Environment(\.openURL) private var openURL

    // Dependency injections (commented until implementations are ready)
    // private let authManager = AuthenticationManager()
    // private let locationManager = CLLocationManager()

    var body: some View {
        NavigationView {
            List {
                // SHARING SECTION
                Section(header: Text("Sharing Options")) {
                    Toggle("Sanitize File Name", isOn: $sanitizeFileName)
                        .onChange(of: sanitizeFileName) { _, newValue in
                            print("Sanitize file name: \(newValue)")
                            // TODO: Update user preferences
                        }

                    Toggle("Sanitize Metadata", isOn: $sanitizeMetadata)
                        .onChange(of: sanitizeMetadata) { _, newValue in
                            print("Sanitize metadata: \(newValue)")
                            // TODO: Update user preferences
                        }

                    Text("When enabled, personal information will be removed from photos before sharing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // PRIVACY & DETECTION SECTION
                Section(header: Text("Privacy & Detection")) {
                    Toggle("Face Detection", isOn: $showFaceDetection)
                        .onChange(of: showFaceDetection) { _, newValue in
                            print("Face detection: \(newValue)")
                        }

                    Text("When enabled, faces can be detected in photos for privacy protection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // LOCATION SECTION
                Section(header: Text("Location")) {
                    Toggle("Include Location Data", isOn: $includeLocationData)
                        .onChange(of: includeLocationData) { _, newValue in
                            locationManager.setIncludeLocationData(newValue)
                        }

                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(locationManager.getAuthorizationStatusString())
                            .foregroundColor(locationStatusColor)
                    }

                    let permissionNotDetermined = locationManager.authorizationStatus == .notDetermined
                    
                    Button {
                        if permissionNotDetermined {
                            locationManager.requestLocationPermission()
                        } else {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                        } label: {
                            Text(permissionNotDetermined
                                 ? "Request Location Permission"
                                 : "Manage Permission in Settings")
                        }

                    Text("When enabled, location data will be embedded in newly captured photos. Location requires permission and GPS availability.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                // DECOY PHOTOS SECTION
                Section(header: Text("Decoy Photos")) {
                    Button("Mark Decoys") {
                        isSelectingDecoys = true
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

                    Picker("Session Timeout", selection: $sessionTimeout) {
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("Never").tag(0)
                    }
                    .onChange(of: sessionTimeout) { _, newValue in
                        print("Session timeout changed to \(newValue) minutes")
                        // TODO: Update user preferences
                    }

                    Toggle("Biometric Authentication", isOn: $biometricEnabled)
                        .onChange(of: biometricEnabled) { _, newValue in
                            print("Biometric auth: \(newValue)")
                            // TODO: Update auth manager
                            // authManager.isBiometricEnabled = newValue
                        }
                        
                    Toggle("Require PIN when app resumes", isOn: $requirePINOnResume)
                        .onChange(of: requirePINOnResume) { _, newValue in
                            print("Require PIN on resume: \(newValue)")
                            pinManager.setRequirePINOnResume(newValue)
                        }
                }

                // APP PIN SECTION
                Section(header: Text("App PIN"), footer: Text("Enter a new 4-digit PIN twice to change your app security PIN")) {
                    SecureField("New PIN (4 digits)", text: $appPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode) // Prevents keychain suggestions
                        .onChange(of: appPIN) { _, newValue in
                            // Limit to 4 digits
                            if newValue.count > 4 {
                                appPIN = String(newValue.prefix(4))
                            }
                            
                            // Only allow numbers
                            if !newValue.allSatisfy({ $0.isNumber }) {
                                appPIN = newValue.filter { $0.isNumber }
                            }
                            
                            // Clear any previous errors when typing
                            if showPINError {
                                showPINError = false
                            }
                        }
                    
                    SecureField("Confirm New PIN", text: $confirmAppPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode)
                        .onChange(of: confirmAppPIN) { _, newValue in
                            // Limit to 4 digits
                            if newValue.count > 4 {
                                confirmAppPIN = String(newValue.prefix(4))
                            }
                            
                            // Only allow numbers
                            if !newValue.allSatisfy({ $0.isNumber }) {
                                confirmAppPIN = newValue.filter { $0.isNumber }
                            }
                            
                            // Clear any previous errors when typing
                            if showPINError {
                                showPINError = false
                            }
                        }
                    
                    if showPINError {
                        Text(pinErrorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.vertical, 5)
                    }
                    
                    if showPINSuccess {
                        Text("PIN updated successfully!")
                            .foregroundColor(.green)
                            .font(.caption)
                            .padding(.vertical, 5)
                    }

                    Button("Update PIN") {
                        resetAppPIN()
                    }
                    .disabled(appPIN.isEmpty || confirmAppPIN.isEmpty)
                }

                // EMERGENCY ERASURE SECTION (POISON PILL)
                Section(header: Text("Emergency Erasure"), footer: Text("If this PIN is entered, all photos will be immediately deleted")) {
                    SecureField("Set Emergency PIN", text: $poisonPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode) // Prevents keychain suggestions

                    Button("Save Emergency PIN") {
                        if !poisonPIN.isEmpty {
                            print("Setting poison PIN")
                            // authManager.setPoisonPIN(poisonPIN)
                            poisonPIN = ""
                        }
                    }
                    .foregroundColor(.red)
                    .disabled(poisonPIN.isEmpty)
                }

                // SECURITY RESET SECTION
                Section {
                    Button("Reset All Security Settings") {
                        showResetConfirmation = true
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
            .onAppear {
                // Initialize includeLocationData from the LocationManager
                includeLocationData = locationManager.shouldIncludeLocationData
                
                // Initialize PIN on resume setting
                requirePINOnResume = pinManager.requirePINOnResume
            }
            .alert(isPresented: $showResetConfirmation) {
                Alert(
                    title: Text("Reset Security Settings"),
                    message: Text("Are you sure you want to reset all security settings to default? This action cannot be undone."),
                    primaryButton: .destructive(Text("Reset")) {
                        resetSecuritySettings()
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(isPresented: $isSelectingDecoys) {
                // Reset the selection flag when the sheet is dismissed
                isSelectingDecoys = false
            } content: {
                // Initialize SecureGalleryView in decoy selection mode
                SecureGalleryView(selectingDecoys: true)
            }
        }
    }

    // MARK: - Helper Properties

    private var locationStatusColor: Color {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    // MARK: - Helper Methods

    /// Reset or change the app PIN
    private func resetAppPIN() {
        // Reset any previous feedback
        showPINError = false
        showPINSuccess = false
        
        // Validate PIN
        if appPIN.count != 4 {
            showPINError = true
            pinErrorMessage = "PIN must be 4 digits"
            return
        }
        
        // Check if PINs match
        if appPIN != confirmAppPIN {
            showPINError = true
            pinErrorMessage = "PINs do not match"
            return
        }
        
        // Update the PIN using PIN manager
        pinManager.setPIN(appPIN)
        
        // Show success message
        showPINSuccess = true
        
        // Clear the fields
        appPIN = ""
        confirmAppPIN = ""
        
        // Clear success message after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.showPINSuccess = false
        }
        
        print("App PIN has been updated")
    }
    
    private func resetSecuritySettings() {
        // Reset all security settings to default values
        biometricEnabled = false
        sessionTimeout = 5
        appPIN = ""
        confirmAppPIN = ""
        poisonPIN = ""
        showPINError = false
        showPINSuccess = false

        // In a real implementation:
        // authManager.resetSecuritySettings()
        print("Security settings have been reset")
    }
}

//
//  SettingsView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import SwiftUI
import Combine

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
    @State private var poisonPIN = ""
    @State private var showResetConfirmation = false
    
    // Decoy photos
    @State private var isSelectingDecoys = false
    
    // Location permissions
    @State private var locationPermissionStatus = "Not Determined"
    
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
                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(locationPermissionStatus)
                            .foregroundColor(locationStatusColor)
                    }
                    
                    Button("Check Location Permission") {
                        checkLocationPermission()
                    }
                    
                    Text("Location data can be embedded in photos when permission is granted")
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
                }
                
                // APP PIN SECTION
                Section(header: Text("App PIN"), footer: Text("Set an app-specific PIN for additional security")) {
                    SecureField("Set App PIN", text: $appPIN)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled(true)
                        .textContentType(.oneTimeCode) // Prevents keychain suggestions
                    
                    Button("Save App PIN") {
                        if !appPIN.isEmpty {
                            print("Setting app PIN")
                            // authManager.setAppPIN(appPIN)
                            appPIN = ""
                        }
                    }
                    .disabled(appPIN.isEmpty)
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
                checkLocationPermission()
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
        switch locationPermissionStatus {
        case "Authorized":
            return .green
        case "Denied", "Restricted":
            return .red
        default:
            return .orange
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkLocationPermission() {
        // In a real implementation, this would use CLLocationManager
        // For now we'll simulate the permission check
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Simulate different permission states for demo purposes
            let statuses = ["Not Determined", "Authorized", "Denied", "Restricted"]
            self.locationPermissionStatus = statuses[Int.random(in: 0..<statuses.count)]
        }
    }
    
    private func resetSecuritySettings() {
        // Reset all security settings to default values
        biometricEnabled = false
        sessionTimeout = 5
        appPIN = ""
        poisonPIN = ""
        
        // In a real implementation:
        // authManager.resetSecuritySettings()
        print("Security settings have been reset")
    }
}

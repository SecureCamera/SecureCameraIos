//
//  SettingsView.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/18/25.
//

import Combine
import CoreLocation
import SwiftUI
import FactoryKit

@_exported import Foundation

struct SettingsView: View {
    // Appearance setting
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system
    
    // ViewModel
    @StateObject private var viewModel = SettingsViewModel()
    
    // Location Manager (still needed for authorization status)
    @InjectedObject(\.locationRepository) private var locationRepository: LocationRepository
    
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var nav: AppNavigationState

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

                // LOCATION SECTION
                Section(header: Text("Location")) {
                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(locationRepository.getAuthorizationStatusString())
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
                    }
                    .onChange(of: viewModel.sessionTimeout) { _, newValue in
                        viewModel.updateSessionTimeout(newValue)
                    }
                }

                // EMERGENCY ERASURE SECTION (POISON PILL)
                Section(header: Text("Poison Pill"), footer: Text("Emergency security feature that permanently deletes all data when triggered")) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Emergency Data Deletion")
                                .font(.body)
                                .fontWeight(.medium)
                            
                            Text(viewModel.hasPoisonPill ? "Poison pill is configured and ready" : "Set up a special PIN that will immediately delete all photos and encryption keys")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: viewModel.hasPoisonPill ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(viewModel.hasPoisonPill ? .green : .orange)
                            .font(.system(size: 20))
                    }
                    
                    if viewModel.hasPoisonPill {
                        Button("Remove Poison Pill") {
                            viewModel.doShowRemovePoisonPillConfirmation()
                        }
                        .foregroundColor(.red)
                    } else {
                        Button("Setup Poison Pill") {
                            nav.dismissAll()
                            nav.navigate(to: .poisonPillSetupWizard)
                        }
                        .foregroundColor(.orange)
                    }
                }
                
                if viewModel.hasPoisonPill {
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
                }

                // SECURITY RESET SECTION
                Section {
                    Button("Perform Security Reset") {
                        viewModel.showSecurityResetConfirmation()
                    }
                    .foregroundColor(.red)

                } footer: {
                    Text("Resets everything, deletes all photos and encryption keys.")
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
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                viewModel.checkPoisonPillStatus()
            }
            .onChange(of: viewModel.shouldOpenSettings) { _, shouldOpen in
                if shouldOpen {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                    viewModel.shouldOpenSettings = false
                }
            }
            .alert("Reset Security Settings", isPresented: $viewModel.showResetConfirmation) {
                Button("Reset", role: .destructive) {
                    viewModel.resetSecuritySettings()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to reset all security settings to default? This action cannot be undone.")
            }
            .alert("Remove Poison Pill", isPresented: $viewModel.showRemovePoisonPillConfirmation) {
                Button("Remove", role: .destructive) {
                    viewModel.removePoisonPill()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to remove the poison pill? You will need to set it up again if you want this emergency protection.")
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
        .securityManaged()
    }
}

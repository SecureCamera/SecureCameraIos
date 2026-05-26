//
//  AboutView.swift
//  SnapSafe
//
//  Created by Claude on 9/25/25.
//

import SwiftUI
import FactoryKit

struct AboutView: View {
    @StateObject private var viewModel = AboutViewModel()
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)
                    
                    Text("SnapSafe")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Secure Photo Storage")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Version \(viewModel.appVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
            }
            
            Section("About") {
                Text("SnapSafe is a privacy-focused camera app designed to protect your sensitive photos with strong encryption and secure storage.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                
                Button("SnapSafe.org") {
                    if let url = URL(string: "https://snapsafe.org") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            }
            
            Section("Community") {
                Text("Come engage with our community, discover more Free and Open Source Software!")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                
                Button("Join our Discord") {
                    if let url = URL(string: "https://discord.gg/ju2RQa5x8W") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            }
            
            Section("Open Source") {
                Text("SnapSafe is an open source project. View the source code on GitHub:")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/SecureCamera/SecureCameraIos/") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            }
            
            Section("Privacy") {
                Text("SnapSafe stores all data locally on your device. No data is transmitted to external servers.")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                
                Button("Privacy Policy") {
                    if let url = URL(string: "https://github.com/SecureCamera/SecureCameraIos/blob/main/PRIVACY.md") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            }
            
            Section("Report Bugs") {
                Text("Found a bug? Report it on GitHub:")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                
                Button("Report Bug") {
                    if let url = URL(string: "https://github.com/SecureCamera/SecureCameraIos/issues/new") {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.blue)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}

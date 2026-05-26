//
//  DeveloperToolsView.swift
//  SnapSafe
//
//  Created by Assistant on 5/25/26.
//

import SwiftUI

/// A development view for accessing testing tools during development
/// This should be removed or gated in production builds
@available(iOS 18.0, *)
struct DeveloperToolsView: View {
    @EnvironmentObject private var nav: AppNavigationState
    
    var body: some View {
        NavigationView {
            List {
                Section("Testing Tools") {
                    Button(action: {
                        nav.navigate(to: .videoExportTest)
                    }) {
                        HStack {
                            Image(systemName: "video.badge.waveform")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading) {
                                Text("Video Export Test")
                                    .font(.headline)
                                Text("Test video creation and export functionality on simulator")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                Section(footer: Text("These tools are for development and testing purposes only. They will not be available in production builds.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Developer Tools")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        nav.navigateBack()
                    }
                }
            }
        }
    }
}
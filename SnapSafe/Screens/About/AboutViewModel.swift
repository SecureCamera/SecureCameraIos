//
//  AboutViewModel.swift
//  SnapSafe
//
//  Created by Claude on 9/25/25.
//

import Foundation

@MainActor
final class AboutViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var appVersion: String = "1.0.0"
    @Published private(set) var buildNumber: String = "1"
    
    // MARK: - Initialization
    init() {
        loadAppInfo()
    }
    
    // MARK: - Private Methods
    private func loadAppInfo() {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            appVersion = version
        }
        
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            buildNumber = build
        }
    }
}

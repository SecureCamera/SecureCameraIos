//
//  LocationManager.swift
//  SnapSafe
//
//  Created by Bill Booth on 5/19/25.
//

import Combine
import CoreGraphics
import CoreLocation
import Foundation
import ImageIO
import Logging


class LocationRepository: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    // Published properties that can be observed by SwiftUI views
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?

    // The user's iOS-level Precise/Approximate choice. Only meaningful while
    // location access is authorized; the system reports `.fullAccuracy` by
    // default otherwise.
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        // Get the current authorization status
        authorizationStatus = locationManager.authorizationStatus
        accuracyAuthorization = locationManager.accuracyAuthorization

        // Start tracking if we already have permission
        startUpdatingLocationIfAuthorized()
    }

    // Function to request location permission
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // Function to start location updates if we have permission
    private func startUpdatingLocationIfAuthorized() {
        // Automatically start updates if we have permission
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }

    // Function to stop location updates
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // Function to get a user-friendly status string
    func getAuthorizationStatusString() -> String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not Determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedAlways, .authorizedWhenInUse:
            return "Authorized"
        @unknown default:
            return "Unknown"
        }
    }

    // Whether location access is currently granted (when-in-use or always).
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    // User-friendly string for the user's iOS-level Precise/Approximate choice.
    func getAccuracyAuthorizationString() -> String {
        Self.accuracyDisplayString(for: accuracyAuthorization)
    }

    // Maps the iOS accuracy authorization to a display string. Pure and static
    // so the mapping can be unit-tested without a live CLLocationManager.
    static func accuracyDisplayString(for accuracy: CLAccuracyAuthorization) -> String {
        switch accuracy {
        case .fullAccuracy:
            return "Precise"
        case .reducedAccuracy:
            return "Approximate"
        @unknown default:
            return "Unknown"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationRepository: CLLocationManagerDelegate {
    // Called when the authorization status changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization

        // Automatically start or stop location updates based on authorization status
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else {
            stopUpdatingLocation()
            // Clear cached location when permission is revoked
            lastLocation = nil
        }
    }

    // Called when a new location is available
    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Use the most recent location
        lastLocation = location
    }

    // Called when there's an error getting location
    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        Logger.app.error("Location Manager failed with error: \(error.localizedDescription)")
    }
}

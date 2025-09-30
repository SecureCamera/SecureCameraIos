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
    @Published var shouldIncludeLocationData: Bool = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        // Load saved user preference for location data inclusion
        shouldIncludeLocationData = UserDefaults.standard.bool(forKey: "shouldIncludeLocationData")

        // Get the current authorization status
        authorizationStatus = locationManager.authorizationStatus
    }

    // Function to request location permission
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // Function to start location updates if we have permission
    func startUpdatingLocation() {
        // Only start updates if we have permission and the user wants location data
        if authorizationStatus == .authorizedWhenInUse && shouldIncludeLocationData {
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
}

// MARK: - CLLocationManagerDelegate

extension LocationRepository: CLLocationManagerDelegate {
    // Called when the authorization status changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        // Start or stop location updates based on new authorization
        if shouldIncludeLocationData && (authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways) {
            startUpdatingLocation()
        } else {
            stopUpdatingLocation()
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

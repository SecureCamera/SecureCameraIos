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

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()

    // Published properties that can be observed by SwiftUI views
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var shouldIncludeLocationData: Bool = false

    // Singleton instance for app-wide access
    static let shared = LocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest

        // Load saved user preference for location data inclusion
        shouldIncludeLocationData = UserDefaults.standard.bool(
            forKey: "shouldIncludeLocationData")

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
        if authorizationStatus == .authorizedWhenInUse,
           shouldIncludeLocationData
        {
            locationManager.startUpdatingLocation()
        }
    }

    // Function to stop location updates
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // Function to get the current location metadata for a photo
    func getCurrentLocationMetadata() -> [String: Any]? {
        // If the user doesn't want location data or we don't have permission, return nil
        if !shouldIncludeLocationData
            || (authorizationStatus != .authorizedWhenInUse
                && authorizationStatus != .authorizedAlways)
        {
            return nil
        }

        // If we have a location, create GPS metadata
        if let location = lastLocation {
            // Create GPS dictionary
            var gpsDict: [String: Any] = [:]

            // Latitude
            let latitude = location.coordinate.latitude
            let latitudeRef = latitude >= 0 ? "N" : "S"
            gpsDict[String(kCGImagePropertyGPSLatitudeRef)] = latitudeRef
            gpsDict[String(kCGImagePropertyGPSLatitude)] = abs(latitude)

            // Longitude
            let longitude = location.coordinate.longitude
            let longitudeRef = longitude >= 0 ? "E" : "W"
            gpsDict[String(kCGImagePropertyGPSLongitudeRef)] = longitudeRef
            gpsDict[String(kCGImagePropertyGPSLongitude)] = abs(longitude)

            // Altitude
            if location.verticalAccuracy > 0 {
                gpsDict[String(kCGImagePropertyGPSAltitudeRef)] =
                    location.altitude < 0 ? 1 : 0
                gpsDict[String(kCGImagePropertyGPSAltitude)] = abs(
                    location.altitude)
            }

            // Timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            gpsDict[String(kCGImagePropertyGPSDateStamp)] =
                dateFormatter.string(from: location.timestamp)

            // Create the GPS metadata dictionary
            return [String(kCGImagePropertyGPSDictionary): gpsDict]
        }

        return nil
    }

    // Function to set the user's preference for including location data
    func setIncludeLocationData(_ include: Bool) {
        shouldIncludeLocationData = include
        UserDefaults.standard.set(include, forKey: "shouldIncludeLocationData")

        if include {
            startUpdatingLocation()
        } else {
            stopUpdatingLocation()
        }
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

extension LocationManager: CLLocationManagerDelegate {
    // Called when the authorization status changes
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        // Start or stop location updates based on new authorization
        if shouldIncludeLocationData,
           authorizationStatus == .authorizedWhenInUse
           || authorizationStatus == .authorizedAlways
        {
            startUpdatingLocation()
        } else {
            stopUpdatingLocation()
        }
    }

    // Called when a new location is available
    func locationManager(
        _: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }

        // Use the most recent location
        lastLocation = location
    }

    // Called when there's an error getting location
    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        print(
            "Location Manager failed with error: \(error.localizedDescription)")
    }
}

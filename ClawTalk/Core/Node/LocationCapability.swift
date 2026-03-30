import Foundation
import CoreLocation

enum LocationCapability {

    struct LocationResult: Encodable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let speed: Double
        let course: Double
        let timestamp: String
    }

    enum LocationError: LocalizedError {
        case denied
        case unavailable
        case timeout

        var errorDescription: String? {
            switch self {
            case .denied: return "Location permission denied"
            case .unavailable: return "Location services unavailable"
            case .timeout: return "Location request timed out"
            }
        }
    }

    static func getLocation() async throws -> LocationResult {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.unavailable
        }

        let delegate = LocationDelegate()
        let manager = CLLocationManager()
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyBest

        // Request permission if needed
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Wait for authorization
            try await delegate.waitForAuthorization()
        } else if status == .denied || status == .restricted {
            throw LocationError.denied
        }

        manager.requestLocation()

        let location = try await delegate.waitForLocation()
        let formatter = ISO8601DateFormatter()

        return LocationResult(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            speed: location.speed,
            course: location.course,
            timestamp: formatter.string(from: location.timestamp)
        )
    }
}

// MARK: - CLLocationManager Delegate

private class LocationDelegate: NSObject, CLLocationManagerDelegate {
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Error>?

    func waitForLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
        }
    }

    func waitForAuthorization() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            authContinuation?.resume()
            authContinuation = nil
        } else if status == .denied || status == .restricted {
            authContinuation?.resume(throwing: LocationCapability.LocationError.denied)
            authContinuation = nil
        }
    }
}

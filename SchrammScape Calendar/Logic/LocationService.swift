//
//  LocationService.swift
//  SchrammScape Calendar
//
//  One-shot current-location lookup using Core Location's async API.
//  Requires the NSLocationWhenInUseUsageDescription Info.plist key.
//

import CoreLocation

nonisolated enum LocationService {

    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Location access was denied. Enable it in Settings › Privacy › Location Services."
            case .unavailable:
                return "Your current location isn't available right now."
            }
        }
    }

    /// Waits for the first location fix; Core Location shows the permission
    /// prompt automatically on first use.
    static func currentLocation() async throws -> CLLocation {
        for try await update in CLLocationUpdate.liveUpdates() {
            if update.authorizationDenied {
                throw LocationError.denied
            }
            if let location = update.location {
                return location
            }
            // No fix yet (e.g. still prompting); keep waiting for the next update.
        }
        throw LocationError.unavailable
    }
}

//
//  GeocodingService.swift
//  SchrammScape Calendar
//
//  Address → coordinate lookups via MapKit's MKGeocodingRequest,
//  shared by customer address validation and the My Day map.
//

import Foundation
import MapKit

nonisolated enum GeocodingService {

    /// Resolves an address string to a location, or nil if Maps can't find it.
    static func geocode(_ address: String) async -> CLLocation? {
        guard let request = MKGeocodingRequest(addressString: address) else { return nil }
        let items: [MKMapItem]? = await withCheckedContinuation { continuation in
            request.getMapItems { mapItems, _ in
                continuation.resume(returning: mapItems)
            }
        }
        return items?.first?.location
    }
}

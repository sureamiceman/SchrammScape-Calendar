//
//  DriveTimeService.swift
//  SchrammScape Calendar
//
//  Expected driving times between coordinates via MKDirections ETAs.
//  Results persist to disk because customer addresses rarely change,
//  so repeat optimizations skip the network almost entirely.
//

import Foundation
import MapKit

@MainActor
final class DriveTimeService {
    static let shared = DriveTimeService()

    private var cache: [String: Double] = [:]
    private let cacheURL = URL.documentsDirectory.appendingPathComponent("drive-time-cache.json")

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let stored = try? JSONDecoder().decode([String: Double].self, from: data) {
            cache = stored
        }
    }

    /// Expected driving time in seconds between two points.
    /// Falls back to a 30 mph straight-line estimate when the directions
    /// service is throttled or unreachable, so route optimization always finishes.
    func travelTime(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Double {
        let key = Self.cacheKey(a, b)
        if let cached = cache[key] { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: a.latitude, longitude: a.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: b.latitude, longitude: b.longitude), address: nil)
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculateETA()
            cache[key] = response.expectedTravelTime
            saveCache()
            return response.expectedTravelTime
        } catch {
            // 13.4 m/s ≈ 30 mph. Not cached, so a real ETA can replace it next run.
            return RouteOptimizer.distance(a, b) / 13.4
        }
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL)
        }
    }

    /// Symmetric key (A→B stored once for both directions) with coordinates
    /// rounded to ~11 m so nearby GPS fixes reuse the same entry.
    private static func cacheKey(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        func rounded(_ c: CLLocationCoordinate2D) -> String {
            String(format: "%.4f,%.4f", c.latitude, c.longitude)
        }
        return [rounded(a), rounded(b)].sorted().joined(separator: ">")
    }
}

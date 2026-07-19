//
//  DriveTimeService.swift
//  SchrammScape Calendar
//
//  Expected driving time AND road distance between coordinates via
//  MKDirections routes. Results persist to disk because customer addresses
//  rarely change, so repeat optimizations skip the network almost entirely.
//

import Foundation
import MapKit

@MainActor
final class DriveTimeService {
    static let shared = DriveTimeService()

    /// One driving leg between two points.
    struct Leg: Codable {
        var seconds: Double
        var meters: Double

        var miles: Double { meters / 1609.344 }
    }

    private var cache: [String: Leg] = [:]
    // v2: legs with distance (the old seconds-only cache is simply orphaned).
    private let cacheURL = URL.documentsDirectory.appendingPathComponent("drive-cache-v2.json")

    private init() {
        if let data = try? Data(contentsOf: cacheURL),
           let stored = try? JSONDecoder().decode([String: Leg].self, from: data) {
            cache = stored
        }
    }

    /// Expected driving time in seconds between two points (route optimizer's
    /// cost function — unchanged signature for all existing callers).
    func travelTime(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Double {
        await travelLeg(from: a, to: b).seconds
    }

    /// Driving time and road distance between two points. Falls back to a
    /// 30 mph straight-line estimate when the directions service is throttled
    /// or unreachable, so optimization and mileage logging always complete.
    func travelLeg(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Leg {
        let key = Self.cacheKey(a, b)
        if let cached = cache[key] { return cached }

        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: a.latitude, longitude: a.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: b.latitude, longitude: b.longitude), address: nil)
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { throw MKError(.directionsNotFound) }
            let leg = Leg(seconds: route.expectedTravelTime, meters: route.distance)
            cache[key] = leg
            saveCache()
            return leg
        } catch {
            // 13.4 m/s ≈ 30 mph over the straight-line distance.
            // Not cached, so a real route can replace it next run.
            let straightLine = RouteOptimizer.distance(a, b)
            return Leg(seconds: straightLine / 13.4, meters: straightLine)
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

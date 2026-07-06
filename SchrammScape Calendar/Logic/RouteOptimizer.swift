//
//  RouteOptimizer.swift
//  SchrammScape Calendar
//
//  Orders a day's stops for the cheapest open-ended route from a starting
//  point, using a caller-provided pairwise cost (e.g. drive time).
//  Nearest-neighbor construction refined by 2-opt over a precomputed matrix.
//

import CoreLocation

nonisolated enum RouteOptimizer {

    struct Stop {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
    }

    struct Result {
        let route: [Stop]
        /// Cost of visiting the stops in their original order.
        let originalCost: Double
        /// Cost of the optimized order, in the same unit as `cost` returns.
        let optimizedCost: Double
    }

    /// Optimizes the visiting order starting at `start`. The cost function is
    /// awaited once per unique pair (assumed symmetric), so expensive costs
    /// like network ETAs are only fetched for the matrix build.
    static func optimize(
        from start: CLLocationCoordinate2D,
        stops: [Stop],
        cost: (CLLocationCoordinate2D, CLLocationCoordinate2D) async -> Double
    ) async -> Result {
        guard stops.count > 1 else {
            return Result(route: stops, originalCost: 0, optimizedCost: 0)
        }

        // Pairwise cost matrix; index 0 is the starting location.
        let points = [start] + stops.map(\.coordinate)
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: points.count), count: points.count)
        for i in points.indices {
            for j in (i + 1)..<points.count {
                let value = await cost(points[i], points[j])
                matrix[i][j] = value
                matrix[j][i] = value
            }
        }

        func routeCost(_ order: [Int]) -> Double {
            var total = 0.0
            var current = 0
            for index in order {
                total += matrix[current][index]
                current = index
            }
            return total
        }

        // Nearest-neighbor construction over matrix indices 1...n.
        var remaining = Set(1...stops.count)
        var order: [Int] = []
        var current = 0
        while let next = remaining.min(by: { matrix[current][$0] < matrix[current][$1] }) {
            remaining.remove(next)
            order.append(next)
            current = next
        }

        // 2-opt refinement: reverse segments while it lowers the total cost.
        var improved = true
        while improved {
            improved = false
            for i in 0..<(order.count - 1) {
                for j in (i + 1)..<order.count {
                    var candidate = order
                    candidate[i...j].reverse()
                    if routeCost(candidate) + 1 < routeCost(order) {
                        order = candidate
                        improved = true
                    }
                }
            }
        }

        return Result(
            route: order.map { stops[$0 - 1] },
            originalCost: routeCost(Array(1...stops.count)),
            optimizedCost: routeCost(order)
        )
    }

    /// Great-circle distance in meters.
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Seconds → "42 min" or "1 hr 5 min".
    static func minutesLabel(_ seconds: Double) -> String {
        WorkSummaryBuilder.durationLabel(max(1, Int((seconds / 60).rounded())))
    }
}

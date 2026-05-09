import Foundation

/// Public OSRM demo router (driving profile). Replace base URL for self-hosted OSRM in production.
///
/// All systems can depend on this via ``GuardianHQApp`` / ``EnvironmentObject``.
@MainActor
final class OSMRoutingService: ObservableObject {
    /// e.g. `https://router.project-osrm.org` — no trailing slash.
    var baseURLString: String

    private let urlSession: URLSession

    init(baseURLString: String = "https://router.project-osrm.org", urlSession: URLSession = .shared) {
        self.baseURLString = baseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.urlSession = urlSession
    }

    /// Ordered coordinates along the road network from `from` to `to` (inclusive of endpoints).
    func routeDrivingCoordinates(from: RouteCoordinate, to: RouteCoordinate) async throws -> [RouteCoordinate] {
        let a = normalize(from)
        let b = normalize(to)
        guard distanceMeters(a, b) > 2 else { return [a, b] }

        let urlString =
            "\(baseURLString)/route/v1/driving/\(a.lon),\(a.lat);\(b.lon),\(b.lat)?overview=full&geometries=geojson"
        guard let url = URL(string: urlString) else {
            throw OSMRoutingError.badURL
        }

        let (data, response) = try await urlSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
            throw OSMRoutingError.httpStatus
        }

        let decoded = try JSONDecoder().decode(OSRMRouteResponse.self, from: data)
        guard let coords = decoded.routes.first?.geometry.coordinates, coords.count >= 2 else {
            throw OSMRoutingError.noGeometry
        }

        var out: [RouteCoordinate] = []
        out.reserveCapacity(coords.count)
        for pair in coords where pair.count >= 2 {
            out.append(RouteCoordinate(lat: pair[1], lon: pair[0]))
        }
        // Full geometry is needed for turn-aware simplification in ``MissionTaskPathSegmentEditing``.
        // Only cap extreme polylines so parsing stays bounded.
        if out.count > Self.maxReturnedCoordinates {
            out = Self.uniformStrideSample(out, targetCount: Self.maxReturnedCoordinates)
        }
        if let first = out.first, Self.haversineMeters(first, a) > 1 { out.insert(a, at: 0) }
        if let last = out.last, Self.haversineMeters(last, b) > 1 { out.append(b) }
        return out
    }

    /// Hard cap on vertices returned to callers (``MissionTaskPathSegmentEditing`` reduces further).
    private static let maxReturnedCoordinates = 4_000

    private static func uniformStrideSample(_ coords: [RouteCoordinate], targetCount: Int) -> [RouteCoordinate] {
        guard coords.count > targetCount, targetCount >= 3 else { return coords }
        let step = max(1, coords.count / targetCount)
        var result: [RouteCoordinate] = []
        var i = 0
        while i < coords.count {
            result.append(coords[i])
            i += step
        }
        if result.last.map({ haversineMeters($0, coords.last!) > 0.5 }) ?? true {
            result.append(coords.last!)
        }
        return result
    }

    private func normalize(_ c: RouteCoordinate) -> RouteCoordinate {
        RouteCoordinate(lat: c.lat, lon: c.lon)
    }

    private func distanceMeters(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Double {
        Self.haversineMeters(a, b)
    }

    private static func haversineMeters(_ a: RouteCoordinate, _ b: RouteCoordinate) -> Double {
        let la = a.lat * .pi / 180
        let lb = b.lat * .pi / 180
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(h), sqrt(1 - h))
        return 6_371_000 * c
    }
}

enum OSMRoutingError: Error {
    case badURL
    case httpStatus
    case noGeometry
}

// MARK: - OSRM JSON (GeoJSON LineString coordinates are [lon, lat])

private struct OSRMRouteResponse: Decodable {
    let routes: [OSRMRoute]
}

private struct OSRMRoute: Decodable {
    let geometry: OSRMGeometry
}

private struct OSRMGeometry: Decodable {
    let coordinates: [[Double]]
}

import Foundation
import Mavsdk

/// Converts ``MissionGeofence`` regions into MAVSDK ``Geofence/GeofenceData`` (polygons + circles) and fleet
/// ``FleetVehicleCommandGeofenceUploadPayload`` rows for ``geofencePolygonsJSON``.
///
/// **Circles** are sent as MAVSDK **circle** primitives (center + radius metres), not polygon rings.
/// **Polygons** reuse template vertices; a repeated closing corner matching the first point is **dropped**
/// before upload so consecutive duplicate coordinates are not sent.
///
/// Fleet geofence JSON carries **horizontal geometry only** for both **polygons** and **circles** (no altitude envelope on the wire).
enum MissionGeofenceMavsdkGeofenceUtilities: Sendable {

    /// Builds MAVSDK polygons for **polygon** fences only (one entry per valid polygon).
    static func mavsdkPolygons(forGeofences fences: [MissionGeofence]) -> [Mavsdk.Geofence.Polygon] {
        geofencePolygonPayloads(forGeofences: fences).map(\.mavsdkPolygon)
    }

    /// Builds MAVSDK circles for **circle** fences only.
    static func mavsdkCircles(forGeofences fences: [MissionGeofence]) -> [Mavsdk.Geofence.Circle] {
        geofenceCirclePayloads(forGeofences: fences).map(\.mavsdkCircle)
    }

    /// Fleet polygon payloads (horizontal geometry for the fleet wire).
    static func geofencePolygonPayloads(forGeofences fences: [MissionGeofence]) -> [FleetVehicleCommandGeofencePolygonPayload] {
        let geom = MissionGeofenceGeometryUtilities()
        var out: [FleetVehicleCommandGeofencePolygonPayload] = []
        out.reserveCapacity(fences.count)
        for fence in fences where fence.shape == .polygon {
            guard let poly = mavsdkPolygon(from: fence, geom: geom) else { continue }
            out.append(FleetVehicleCommandGeofencePolygonPayload(mavsdk: poly))
        }
        return out
    }

    /// Fleet circle payloads (center + radius; horizontal geometry for the fleet wire).
    static func geofenceCirclePayloads(forGeofences fences: [MissionGeofence]) -> [FleetVehicleCommandGeofenceCirclePayload] {
        var out: [FleetVehicleCommandGeofenceCirclePayload] = []
        out.reserveCapacity(fences.count)
        for fence in fences where fence.shape == .circle {
            guard let row = geofenceCirclePayload(from: fence) else { continue }
            out.append(row)
        }
        return out
    }

    /// Combined wire payload for fleet ``geofencePolygonsJSON`` (polygons + circles).
    static func geofenceUploadPayload(forGeofences fences: [MissionGeofence]) -> FleetVehicleCommandGeofenceUploadPayload {
        FleetVehicleCommandGeofenceUploadPayload(
            polygons: geofencePolygonPayloads(forGeofences: fences),
            circles: geofenceCirclePayloads(forGeofences: fences)
        )
    }

    /// JSON string for ``geofencePolygonsJSON`` (object with `polygons` and `circles` arrays).
    static func encodeGeofencePolygonsJSON(forGeofences fences: [MissionGeofence]) throws -> String {
        try geofenceUploadPayload(forGeofences: fences).encodeToJSON()
    }

    /// Decodes fleet ``geofencePolygonsJSON`` into ``MissionGeofence`` rows for Guardian Router (move+park, etc.).
    static func missionGeofences(fromGeofencePolygonsJSON json: String) throws -> [MissionGeofence] {
        let payload = try FleetVehicleCommandGeofenceUploadPayload.decode(fromJSON: json)
        return missionGeofences(fromUploadPayload: payload)
    }

    /// Rebuilds ``MissionGeofence`` models from a fleet upload payload (new ids; horizontal geometry only).
    static func missionGeofences(fromUploadPayload payload: FleetVehicleCommandGeofenceUploadPayload) -> [MissionGeofence] {
        var out: [MissionGeofence] = []
        out.reserveCapacity(payload.polygons.count + payload.circles.count)
        for (index, poly) in payload.polygons.enumerated() {
            let boundary: MissionGeofenceBoundaryKind =
                poly.fenceType.lowercased().contains("exclusion") ? .exclusion : .inclusion
            let verts = poly.points.map { RouteCoordinate(lat: $0.latitudeDeg, lon: $0.longitudeDeg) }
            out.append(
                MissionGeofence(
                    name: "wire-polygon-\(index + 1)",
                    boundary: boundary,
                    shape: .polygon,
                    polygonVertices: verts
                )
            )
        }
        for (index, circle) in payload.circles.enumerated() {
            let boundary: MissionGeofenceBoundaryKind =
                circle.fenceType.lowercased().contains("exclusion") ? .exclusion : .inclusion
            out.append(
                MissionGeofence(
                    name: "wire-circle-\(index + 1)",
                    boundary: boundary,
                    shape: .circle,
                    circleCenter: RouteCoordinate(lat: circle.latitudeDeg, lon: circle.longitudeDeg),
                    circleRadiusMeters: max(1, circle.radiusMeters)
                )
            )
        }
        return out
    }

    /// Chooses the lat/lon point used for ``fencesFilteredForPX4GeofenceUpload``.
    ///
    /// PX4 validates **inclusion** fences against the autopilot’s **current home** (e.g. SIH / spawn),
    /// which can differ slightly from the mission template’s ``RouteMacro/home`` used when authoring.
    /// When hub telemetry reports ``FleetHubVehicleTelemetry/homeLatitudeDeg`` and ``homeLongitudeDeg``,
    /// those take precedence; otherwise the route macro home is used.
    static func px4GeofenceFilterHome(routeMacroHome: RouteCoordinate?, hub: FleetHubVehicleTelemetry?) -> RouteCoordinate? {
        guard let hub else { return routeMacroHome }
        if let lat = hub.homeLatitudeDeg, let lon = hub.homeLongitudeDeg {
            return RouteCoordinate(lat: lat, lon: lon)
        }
        return routeMacroHome
    }

    /// PX4 commonly rejects **inclusion** geofences that do not contain the mission home (RTL anchor).
    /// Exclusion fences are left unchanged. When `home` is `nil`, returns the input list and zero omissions.
    static func fencesFilteredForPX4GeofenceUpload(fences: [MissionGeofence], home: RouteCoordinate?) -> ([MissionGeofence], omittedInclusionCount: Int) {
        guard let home else { return (fences, 0) }
        let geom = MissionGeofenceGeometryUtilities()
        var out: [MissionGeofence] = []
        out.reserveCapacity(fences.count)
        var omitted = 0
        for fence in fences {
            if fence.boundary == .exclusion {
                out.append(fence)
                continue
            }
            if px4InclusionFenceContainsHome(fence, home: home, geom: geom) {
                out.append(fence)
            } else {
                omitted += 1
            }
        }
        return (out, omitted)
    }

    private static func px4InclusionFenceContainsHome(_ fence: MissionGeofence, home: RouteCoordinate, geom: MissionGeofenceGeometryUtilities) -> Bool {
        switch fence.shape {
        case .circle:
            let r = fence.circleRadiusMeters
            guard r >= 1 else { return false }
            let d = MissionTelemetryGeo.horizontalDistanceM(
                lat1: fence.circleCenter.lat,
                lon1: fence.circleCenter.lon,
                lat2: home.lat,
                lon2: home.lon
            )
            return d <= r + 0.5
        case .polygon:
            guard !geom.polygonHasInsufficientVertices(fence.polygonVertices) else { return false }
            return geom.pointInsidePolygonHorizontallyWGS84(point: home, polygonVertices: fence.polygonVertices)
        }
    }

    private static func mavsdkPolygon(from fence: MissionGeofence, geom: MissionGeofenceGeometryUtilities) -> Mavsdk.Geofence.Polygon? {
        guard fence.shape == .polygon else { return nil }
        if geom.polygonHasInsufficientVertices(fence.polygonVertices) { return nil }
        var pts = fence.polygonVertices.map {
            Mavsdk.Geofence.Point(latitudeDeg: $0.lat, longitudeDeg: $0.lon)
        }
        pts = Self.mavsdkFenceOpenRingPoints(pts)
        guard pts.count >= 3 else { return nil }
        return Mavsdk.Geofence.Polygon(points: pts, fenceType: fence.mavsdkFenceType)
    }

    private static func geofenceCirclePayload(from fence: MissionGeofence) -> FleetVehicleCommandGeofenceCirclePayload? {
        guard fence.shape == .circle else { return nil }
        let r = fence.circleRadiusMeters
        guard r >= 1 else { return nil }
        let c = fence.circleCenter
        return FleetVehicleCommandGeofenceCirclePayload(
            fenceType: fence.boundary == .inclusion ? "inclusion" : "exclusion",
            latitudeDeg: c.lat,
            longitudeDeg: c.lon,
            radiusMeters: r
        )
    }

    /// MAVSDK ``assemble_items`` encodes each vertex as a fence mission item with ``param1`` = full point count;
    /// the geofence polygon must not repeat the first coordinate as the last (duplicate consecutive vertex).
    private static func mavsdkFenceOpenRingPoints(_ points: [Mavsdk.Geofence.Point]) -> [Mavsdk.Geofence.Point] {
        guard points.count >= 2 else { return points }
        var out = points
        while out.count >= 2, let f = out.first, let l = out.last,
              abs(f.latitudeDeg - l.latitudeDeg) <= 1e-9, abs(f.longitudeDeg - l.longitudeDeg) <= 1e-9 {
            out.removeLast()
        }
        return out
    }
}

private extension MissionGeofence {
    var mavsdkFenceType: Mavsdk.Geofence.FenceType {
        switch boundary {
        case .inclusion: return .inclusion
        case .exclusion: return .exclusion
        }
    }
}

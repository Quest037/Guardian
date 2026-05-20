import Foundation

/// Run-log helpers for v1 transit **motion proof** (hub pose before/after open-loop drive).
enum TrainingLabTransitMotionProof {
    /// Minimum horizontal hub movement to treat open-loop drive as having moved the vehicle (roadtest tuning).
    static let minObservedHorizontalMotionM = 0.5

    struct Snapshot: Equatable, Sendable {
        var latitudeDeg: Double?
        var longitudeDeg: Double?
        var headingDeg: Double?
        var isArmed: Bool?
        var hasFix: Bool

        var logLine: String {
            guard hasFix, let lat = latitudeDeg, let lon = longitudeDeg else {
                let armed = isArmed.map { $0 ? "armed" : "disarmed" } ?? "armed?"
                return "no GPS fix (\(armed))"
            }
            let armed = isArmed.map { $0 ? "armed" : "disarmed" } ?? "armed?"
            let hdg = headingDeg.map { String(format: "%.0f°", $0) } ?? "hdg?"
            return String(
                format: "lat %.6f lon %.6f %@ %@",
                lat,
                lon,
                hdg,
                armed
            )
        }
    }

    static func snapshot(hub: FleetHubVehicleTelemetry?) -> Snapshot {
        guard let hub,
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else {
            return Snapshot(
                latitudeDeg: hub?.latitudeDeg,
                longitudeDeg: hub?.longitudeDeg,
                headingDeg: hub?.headingDeg ?? hub?.yawDeg,
                isArmed: hub?.isArmed,
                hasFix: false
            )
        }
        return Snapshot(
            latitudeDeg: lat,
            longitudeDeg: lon,
            headingDeg: hub.headingDeg ?? hub.yawDeg,
            isArmed: hub.isArmed,
            hasFix: true
        )
    }

    static func horizontalDeltaM(from start: Snapshot, to end: Snapshot) -> Double? {
        guard start.hasFix, end.hasFix,
              let lat1 = start.latitudeDeg, let lon1 = start.longitudeDeg,
              let lat2 = end.latitudeDeg, let lon2 = end.longitudeDeg
        else { return nil }
        return MissionTelemetryGeo.horizontalDistanceM(
            lat1: lat1,
            lon1: lon1,
            lat2: lat2,
            lon2: lon2
        )
    }

    static func movementSummary(start: Snapshot, end: Snapshot) -> String {
        guard let deltaM = horizontalDeltaM(from: start, to: end) else {
            return "movement unknown (missing GPS at start or end)"
        }
        if deltaM < minObservedHorizontalMotionM {
            return String(
                format: "moved %.2f m (below %.2f m — check arm, PX4 MANUAL, throttle/steering)",
                deltaM,
                minObservedHorizontalMotionM
            )
        }
        return String(format: "moved %.2f m", deltaM)
    }
}

import Foundation

/// Canonical description of simulator-facing state applied over MAVLink (pose + optional SIM params).
///
/// **Single entrypoint:** `FleetLinkService.applySimState(vehicleID:state:autopilotStack:source:)`.
/// Callers build a value (spawn defaults, Mission Control‑E scene, SIM “arm prep” recovery, etc.)
/// and route through that method so parameters stay consistent.
struct FleetSimState: Equatable {
    var latitudeDeg: Double
    var longitudeDeg: Double
    var absoluteAltitudeM: Double?
    var yawDeg: Float
    var batteryVoltageV: Double?
    var ardupilotSimBattCapAh: Float?
    var px4SimBatDrain: Float?
}

extension FleetSimState {
    /// Values aligned with `SitlLaunchRecipe` / `SimSpawnDefaults` at process start; applied again over MAVLink after link-up.
    init(spawnDefaults: SimSpawnDefaults) {
        latitudeDeg = spawnDefaults.latitudeDeg
        longitudeDeg = spawnDefaults.longitudeDeg
        absoluteAltitudeM = spawnDefaults.altitudeM
        yawDeg = Float(spawnDefaults.headingDeg)
        batteryVoltageV = spawnDefaults.batteryVoltageV
        ardupilotSimBattCapAh = nil
        px4SimBatDrain = nil
    }

    /// Hub pose suitable for ``FleetLinkService/applySimState`` “home restore” (lat/lon required; alt + yaw best-effort).
    init?(simHomeRestoreSnapshotFrom hub: FleetHubVehicleTelemetry) {
        guard let lat = hub.latitudeDeg, let lon = hub.longitudeDeg else { return nil }
        latitudeDeg = lat
        longitudeDeg = lon
        absoluteAltitudeM = hub.absoluteAltM ?? hub.altitudeAmslM
        let heading = hub.headingDeg ?? hub.yawDeg ?? 0
        yawDeg = Float(heading)
        batteryVoltageV = nil
        ardupilotSimBattCapAh = nil
        px4SimBatDrain = nil
    }

    /// Floating reserve pool “home” pose for run-complete SIM restore: prefer hub lat/lon when present; otherwise MCS bulk map home; alt/yaw follow hub when available.
    init?(reservePoolSimHomeRestoreStartPose hub: FleetHubVehicleTelemetry?, bulkHome: RouteCoordinate?) {
        let lat: Double
        let lon: Double
        if let hub, let hLat = hub.latitudeDeg, let hLon = hub.longitudeDeg {
            lat = hLat
            lon = hLon
        } else if let bulk = bulkHome {
            lat = bulk.lat
            lon = bulk.lon
        } else {
            return nil
        }
        latitudeDeg = lat
        longitudeDeg = lon
        absoluteAltitudeM = hub?.absoluteAltM ?? hub?.altitudeAmslM
        let heading = hub?.headingDeg ?? hub?.yawDeg ?? 0
        yawDeg = Float(heading)
        batteryVoltageV = nil
        ardupilotSimBattCapAh = nil
        px4SimBatDrain = nil
    }
}

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
}

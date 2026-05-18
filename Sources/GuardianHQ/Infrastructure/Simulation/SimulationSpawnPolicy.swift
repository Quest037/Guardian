import Foundation

/// Temporary product locks for built-in SITL spawn (remove when stack/class policy is configurable).
enum SimulationSpawnPolicy {
    /// UGV universal class always spawns with PX4; ArduPilot requests are ignored.
    static func effectivePlatform(
        for preset: SimulationVehiclePreset,
        requested: SimulationPlatform
    ) -> SimulationPlatform {
        guard preset.fleetVehicleType.universalClass == .ugv else { return requested }
        return .px4
    }

    static func forcesPx4ForUGV(preset: SimulationVehiclePreset) -> Bool {
        preset.fleetVehicleType.universalClass == .ugv
    }
}

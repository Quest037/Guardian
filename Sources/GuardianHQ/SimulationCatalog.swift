import Foundation

/// Autopilot stack used for **built-in SITL** (spawned by the app). MAVLink to a live vehicle stays stack-agnostic.
enum SimulationPlatform: String, Codable, CaseIterable, Identifiable {
    case ardupilot
    case px4

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ardupilot: return "ArduPilot"
        case .px4: return "PX4"
        }
    }
}

/// Prebuilt simulation vehicle presets (each maps to SITL vehicle models + ports once launchers exist).
enum SimulationVehiclePreset: String, Codable, CaseIterable, Identifiable {
    case uavQuadcopter
    case uavFixedWing
    case uavFixedWingVTOL
    case ugvWheeled
    case ugvTracked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uavQuadcopter: return "UAV · Quadcopter"
        case .uavFixedWing: return "UAV · Fixed-wing"
        case .uavFixedWingVTOL: return "UAV · Fixed-wing VTOL"
        case .ugvWheeled: return "UGV · Wheeled"
        case .ugvTracked: return "UGV · Tracked"
        }
    }

    /// Short hint for UI copy (SITL wiring differs per stack; launchers will use `SimulationPlatform` + this preset).
    var categoryLabel: String {
        switch self {
        case .uavQuadcopter, .uavFixedWing, .uavFixedWingVTOL: return "Unmanned aerial"
        case .ugvWheeled, .ugvTracked: return "Ground"
        }
    }
}

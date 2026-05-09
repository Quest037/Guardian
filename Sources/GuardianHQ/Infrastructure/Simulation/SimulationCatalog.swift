import Foundation

/// High-level domain shown on fleet device cards (live and simulated).
enum VehicleDomain: String, CaseIterable {
    case aerial = "Aerial"
    case ground = "Ground"
    case marine = "Marine"
}

/// Autopilot stack used for **built-in SITL** (spawned by the app). Add cases here when new in-app sim launchers ship; pair with `FleetAutopilotStack` for fleet badges.
/// Live hardware uses `FleetAutopilotStack` filled from MAVSDK (`vehicle_stack` bridge events).
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

/// Simulation vehicle kinds (image basename under `Resources/SimulationDevices`, SITL mapping in `SitlLaunchRecipe`).
enum SimulationVehiclePreset: String, Codable, CaseIterable, Identifiable {
    case uavMultirotor = "UAV_Multirotor"
    case uavFixedWing = "UAV_Fixed_Wing"
    case uavVTOL = "UAV_VTOL"
    case ugvWheeled = "UGV_Wheeled"
    case ugvTracked = "UGV_Tracked"
    case ugvLegged = "UGV_Legged"
    case usv = "USV"
    case uuv = "UUV"

    var id: String { rawValue }

    /// Basenames (no `.png`) to try under `SimulationDevices/`, in order — first existing file wins.
    /// Art ships as **`Dev_Sim_<rawValue>.png`** (see repo `Guardian/Resources/SimulationDevices/`); copies for the app bundle live under `Sources/GuardianHQ/Resources/SimulationDevices/`.
    var simulationDeviceImageBasenames: [String] {
        let devSim = "Dev_Sim_\(rawValue)"
        var names = [devSim, rawValue]
        switch self {
        case .uavMultirotor:
            names.append(contentsOf: ["UAV_MultiRotor", "multirotor", "Multirotor", "Quadcopter", "quadcopter"])
        case .uavFixedWing:
            names.append(contentsOf: [
                "UAV_FixedWing", "UAV_Fixed-Wing", "fixed_wing", "FixedWing", "Fixed-wing", "plane", "Plane",
            ])
        case .uavVTOL:
            names.append(contentsOf: ["UAV_Vtol", "vtol", "VTOL", "quadplane", "QuadPlane"])
        case .ugvWheeled:
            names.append(contentsOf: ["wheeled", "Wheeled", "rover", "Rover"])
        case .ugvTracked:
            names.append(contentsOf: ["tracked", "Tracked", "skid"])
        case .ugvLegged:
            names.append(contentsOf: ["legged", "Legged"])
        case .usv:
            names.append(contentsOf: ["usv", "USV_Surface", "surface", "Surface", "boat", "Boat", "ArduBoat"])
        case .uuv:
            names.append(contentsOf: ["uuv", "UUV_Sub", "submarine", "Submarine", "ArduSub"])
        }
        return names
    }

    var displayName: String {
        switch self {
        case .uavMultirotor: return "Multirotor"
        case .uavFixedWing: return "Fixed wing"
        case .uavVTOL: return "VTOL"
        case .ugvWheeled: return "Wheeled UGV"
        case .ugvTracked: return "Tracked UGV"
        case .ugvLegged: return "Legged UGV"
        case .usv: return "Surface vessel"
        case .uuv: return "Underwater"
        }
    }

    var vehicleDomain: VehicleDomain {
        switch self {
        case .uavMultirotor, .uavFixedWing, .uavVTOL:
            return .aerial
        case .ugvWheeled, .ugvTracked, .ugvLegged:
            return .ground
        case .usv, .uuv:
            return .marine
        }
    }

    /// Maps the SITL preset to the granular ``FleetVehicleType`` used for ``FleetVehicleModel.displayShortID``.
    var fleetVehicleType: FleetVehicleType {
        switch self {
        case .uavMultirotor: return .uavCopter
        case .uavFixedWing: return .uavFixedWing
        case .uavVTOL: return .uavVTOL
        case .ugvWheeled: return .ugvWheeled
        case .ugvTracked: return .ugvTracked
        case .ugvLegged: return .ugvLegged
        case .usv: return .usv
        case .uuv: return .uuv
        }
    }
}

extension FleetVehicleType {
    /// Bundled ``SimulationDevices`` PNG basenames for this class — same catalog as the SITL / mission vehicle picker (``SimulationVehiclePreset/simulationDeviceImageBasenames``).
    var defaultSimulationDeviceImageBasenames: [String] {
        let preset: SimulationVehiclePreset
        switch self {
        case .uavCopter: preset = .uavMultirotor
        case .uavFixedWing: preset = .uavFixedWing
        case .uavVTOL: preset = .uavVTOL
        case .ugvWheeled: preset = .ugvWheeled
        case .ugvTracked: preset = .ugvTracked
        case .ugvLegged: preset = .ugvLegged
        case .usv: preset = .usv
        case .uuv: preset = .uuv
        case .unknown: preset = .uavMultirotor
        }
        return preset.simulationDeviceImageBasenames
    }
}

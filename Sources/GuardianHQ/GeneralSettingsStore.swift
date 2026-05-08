import Combine
import Foundation

enum LogRetentionProfile: String, Codable, CaseIterable, Identifiable {
    case short
    case `default`
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .short: return "Short"
        case .default: return "Default"
        case .long: return "Long"
        }
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum SimBatteryDrainRate: String, Codable, CaseIterable, Identifiable {
    case slow
    case normal
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    /// PX4 `SIM_BAT_DRAIN`: full-discharge time in seconds **while armed** (`0` disables). Disarmed = always 100% in stock PX4 SITL.
    var px4FullDischargeSeconds: Float {
        switch self {
        case .slow: return 3600
        case .normal: return 1800
        case .fast: return 900
        }
    }

    /// ArduPilot `SIM_BATT_CAP_AH`: effective simulated pack size.
    /// Smaller pack drains faster for the same current draw profile.
    var ardupilotCapacityAh: Float {
        switch self {
        case .slow: return 10.0
        case .normal: return 5.0
        case .fast: return 2.5
        }
    }
}

struct SimSpawnDefaults: Equatable, Codable {
    var latitudeDeg: Double
    var longitudeDeg: Double
    /// Fixed at 0m by design for cross-domain defaults (UAV/USV/UUV).
    var altitudeM: Double
    /// Initial heading for spawned SIMs (degrees, 0...360). Used for launch seed + early UI fallback.
    var headingDeg: Double
    /// Initial battery seed shown before first real telemetry sample arrives.
    var batteryPercent: Double
    var batteryVoltageV: Double
    var batteryCurrentA: Double

    static let `default` = SimSpawnDefaults(
        latitudeDeg: 47.397742,
        longitudeDeg: 8.545594,
        altitudeM: 0,
        headingDeg: 0,
        batteryPercent: 100,
        batteryVoltageV: 16.0,
        batteryCurrentA: 0
    )

    init(
        latitudeDeg: Double,
        longitudeDeg: Double,
        altitudeM: Double,
        headingDeg: Double,
        batteryPercent: Double,
        batteryVoltageV: Double,
        batteryCurrentA: Double
    ) {
        self.latitudeDeg = latitudeDeg
        self.longitudeDeg = longitudeDeg
        self.altitudeM = altitudeM
        self.headingDeg = headingDeg
        self.batteryPercent = batteryPercent
        self.batteryVoltageV = batteryVoltageV
        self.batteryCurrentA = batteryCurrentA
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitudeDeg = try c.decode(Double.self, forKey: .latitudeDeg)
        longitudeDeg = try c.decode(Double.self, forKey: .longitudeDeg)
        altitudeM = try c.decodeIfPresent(Double.self, forKey: .altitudeM) ?? 0
        headingDeg = try c.decodeIfPresent(Double.self, forKey: .headingDeg) ?? 0
        batteryPercent = try c.decodeIfPresent(Double.self, forKey: .batteryPercent) ?? 100
        batteryVoltageV = try c.decodeIfPresent(Double.self, forKey: .batteryVoltageV) ?? 16.0
        batteryCurrentA = try c.decodeIfPresent(Double.self, forKey: .batteryCurrentA) ?? 0
    }
}

/// Persisted app-wide preferences (General settings).
@MainActor
final class GeneralSettingsStore: ObservableObject {
    private static let defaultsKey = "guardian.generalSettings.v1"

    /// Default stack for **in-app SITL** when the user does not pick ArduPilot vs PX4 per spawn.
    @Published var defaultSimulationPlatform: SimulationPlatform {
        didSet {
            guard defaultSimulationPlatform != oldValue else { return }
            save()
        }
    }

    /// Default basemap for mission route editing and Mission Control live overview (toggle still available in-app).
    @Published var defaultMapTileStyle: MapTileStyle {
        didSet {
            guard defaultMapTileStyle != oldValue else { return }
            save()
        }
    }

    /// Log retention for visible in-app logs.
    @Published var logRetentionProfile: LogRetentionProfile {
        didSet {
            guard logRetentionProfile != oldValue else { return }
            save()
        }
    }

    /// Preferred app appearance; `.system` follows macOS setting.
    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            guard appearanceMode != oldValue else { return }
            save()
        }
    }

    /// Default simulated battery drain rate used by LD/MC-R when enabling drain.
    @Published var defaultSimBatteryDrainRate: SimBatteryDrainRate {
        didSet {
            guard defaultSimBatteryDrainRate != oldValue else { return }
            save()
        }
    }

    /// Default spawn location for newly added simulated vehicles.
    @Published var simSpawnDefaults: SimSpawnDefaults {
        didSet {
            var next = simSpawnDefaults
            // Keep defaults valid and deterministic.
            next.latitudeDeg = min(90, max(-90, next.latitudeDeg))
            next.longitudeDeg = min(180, max(-180, next.longitudeDeg))
            next.altitudeM = 0
            next.headingDeg = ((next.headingDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            next.batteryPercent = min(100, max(0, next.batteryPercent))
            next.batteryVoltageV = min(100, max(0, next.batteryVoltageV))
            next.batteryCurrentA = min(500, max(-500, next.batteryCurrentA))
            if next != simSpawnDefaults {
                simSpawnDefaults = next
                return
            }
            guard simSpawnDefaults != oldValue else { return }
            save()
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        if let loaded = Self.load(from: userDefaults) {
            defaultSimulationPlatform = loaded.defaultSimulationPlatform
            defaultMapTileStyle = loaded.defaultMapTileStyle ?? .standard
            logRetentionProfile = loaded.logRetentionProfile ?? .default
            appearanceMode = loaded.appearanceMode ?? .system
            defaultSimBatteryDrainRate = loaded.defaultSimBatteryDrainRate ?? .normal
            simSpawnDefaults = loaded.simSpawnDefaults ?? .default
        } else {
            defaultSimulationPlatform = .ardupilot
            defaultMapTileStyle = .standard
            logRetentionProfile = .default
            appearanceMode = .system
            defaultSimBatteryDrainRate = .normal
            simSpawnDefaults = .default
        }
    }

    private func save(userDefaults: UserDefaults = .standard) {
        let snapshot = Snapshot(
            defaultSimulationPlatform: defaultSimulationPlatform,
            defaultMapTileStyle: defaultMapTileStyle,
            logRetentionProfile: logRetentionProfile,
            appearanceMode: appearanceMode,
            defaultSimBatteryDrainRate: defaultSimBatteryDrainRate,
            simSpawnDefaults: simSpawnDefaults
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load(from userDefaults: UserDefaults) -> Snapshot? {
        guard let data = userDefaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private struct Snapshot: Codable {
        var defaultSimulationPlatform: SimulationPlatform
        /// Omitted in older saves; treated as `.standard`.
        var defaultMapTileStyle: MapTileStyle?
        /// Omitted in older saves; treated as `.default`.
        var logRetentionProfile: LogRetentionProfile?
        /// Omitted in older saves; treated as `.system`.
        var appearanceMode: AppAppearanceMode?
        /// Omitted in older saves; treated as `.normal`.
        var defaultSimBatteryDrainRate: SimBatteryDrainRate?
        /// Omitted in older saves; treated as `.default`.
        var simSpawnDefaults: SimSpawnDefaults?
    }
}

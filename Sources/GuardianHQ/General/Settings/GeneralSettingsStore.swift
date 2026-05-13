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

/// Navigation rail width when the app opens (user can still toggle with the sidebar control).
enum MainSidebarLaunchMode: String, Codable, CaseIterable, Identifiable {
    /// Persisted as `"reduced"` for compatibility with existing settings files.
    case collapsed = "reduced"
    case expanded

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .collapsed: return "Collapsed"
        case .expanded: return "Expanded"
        }
    }
}

enum SimBatteryDrainRate: String, Codable, CaseIterable, Identifiable {
    /// No timed / integrator drain model while a Mission Control run enables SIM drain (see ``MissionRunOperatorDisplaySettings/simBatteryDrainRateDuringRun``).
    case none
    case slow
    case normal
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        }
    }

    /// Picker order for **Settings → Missions → Mission Run**, **Settings → Live Drive → SIMs**, Live Drive SIM drawer, and per-run Mission Control settings (None + rates).
    static var missionRunPickerCases: [SimBatteryDrainRate] { [.none, .slow, .normal, .fast] }

    /// PX4 `SIM_BAT_DRAIN`: full-discharge time in seconds **while armed** (`0` disables). Disarmed = always 100% in stock PX4 SITL.
    var px4FullDischargeSeconds: Float {
        switch self {
        case .none: return 0
        case .slow: return 3600
        case .normal: return 1800
        case .fast: return 900
        }
    }

    /// ArduPilot `SIM_BATT_CAP_AH`: effective simulated pack size.
    /// Smaller pack drains faster for the same current draw profile.
    var ardupilotCapacityAh: Float {
        switch self {
        case .none: return 0
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

    private let persistenceUserDefaults: UserDefaults

    /// Allowed range for ``missionControlPostponeStepCapSeconds`` (1 min … 48 h).
    static let minMissionPostponeStepCapSeconds = 60
    static let maxMissionPostponeStepCapSeconds = 48 * 3600

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

    /// Main navigation sidebar when the app opens: icons-only rail vs full labels.
    @Published var mainSidebarLaunchMode: MainSidebarLaunchMode {
        didSet {
            guard mainSidebarLaunchMode != oldValue else { return }
            save()
        }
    }

    /// Operator name or call sign for the local user (logs, Mission Control attribution, etc.).
    @Published var callsign: String {
        didSet {
            guard callsign != oldValue else { return }
            save()
        }
    }

    /// **Live Drive** freestyle SIM battery drain (None / Slow / Normal / Fast). Applied when a freestyle control session starts and from the Live Drive SIM settings drawer. Mission Control **running** uses ``missionRunSimBatteryDrainRate`` / per-run ``MissionRunOperatorDisplaySettings/simBatteryDrainRateDuringRun``.
    @Published var liveDriveSimBatteryDrainRate: SimBatteryDrainRate {
        didSet {
            guard liveDriveSimBatteryDrainRate != oldValue else { return }
            save()
        }
    }

    /// Largest one-shot Alter step (Sooner / Later) in Mission Control: scheduled start, task MAVLink deferrals, between-cycle restarts.
    @Published var missionControlPostponeStepCapSeconds: Int {
        didSet {
            let clamped = Self.clampMissionPostponeStepCapSeconds(missionControlPostponeStepCapSeconds)
            if missionControlPostponeStepCapSeconds != clamped {
                missionControlPostponeStepCapSeconds = clamped
                return
            }
            guard missionControlPostponeStepCapSeconds != oldValue else { return }
            save()
        }
    }

    /// When a task is selected on the Mission Control **running** map, hide other tasks’ route geometry and non-selected vehicle clutter (default on).
    @Published var missionControlLiveMapHideOtherTasksOnTaskSelect: Bool {
        didSet {
            guard missionControlLiveMapHideOtherTasksOnTaskSelect != oldValue else { return }
            save()
        }
    }

    /// Default **show mission geofences** on Mission Control **setup** and **running** maps. New runs copy into ``MissionRunOperatorDisplaySettings/showMissionGeofencesOnMap``; MC‑R / MCS maps do not read ``GeneralSettingsStore`` at runtime.
    @Published var missionControlShowMissionGeofencesOnMap: Bool {
        didSet {
            guard missionControlShowMissionGeofencesOnMap != oldValue else { return }
            save()
        }
    }

    /// Mission Control **SITL reset on successful run completion** (default off, persisted). When on, qualifying run completions restore roster SITL poses from the run’s captured snapshots (see README SIM home reset).
    @Published var missionRunResetSitlToStartPoseOnSuccessfulComplete: Bool {
        didSet {
            guard missionRunResetSitlToStartPoseOnSuccessfulComplete != oldValue else { return }
            save()
        }
    }

    /// Default **SIM battery drain while a Mission Control run is executing** (slow / normal / fast / none). New runs copy this into ``MissionRunOperatorDisplaySettings/simBatteryDrainRateDuringRun``; MC‑R applies it to roster SITL streams — not ``liveDriveSimBatteryDrainRate`` (Live Drive settings).
    @Published var missionRunSimBatteryDrainRate: SimBatteryDrainRate {
        didSet {
            guard missionRunSimBatteryDrainRate != oldValue else { return }
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
        persistenceUserDefaults = userDefaults
        if let loaded = Self.load(from: userDefaults) {
            defaultSimulationPlatform = loaded.defaultSimulationPlatform
            defaultMapTileStyle = loaded.defaultMapTileStyle ?? .standard
            logRetentionProfile = loaded.logRetentionProfile ?? .default
            appearanceMode = loaded.appearanceMode ?? .system
            mainSidebarLaunchMode = loaded.mainSidebarLaunchMode ?? .collapsed
            liveDriveSimBatteryDrainRate = loaded.liveDriveSimBatteryDrainRate
                ?? loaded.defaultSimBatteryDrainRate
                ?? .normal
            missionControlPostponeStepCapSeconds = Self.clampMissionPostponeStepCapSeconds(
                loaded.missionControlPostponeStepCapSeconds ?? MissionDelayPolicy.defaultOperatorPostponeStepCapSeconds
            )
            missionControlLiveMapHideOtherTasksOnTaskSelect = loaded.missionControlLiveMapHideOtherTasksOnTaskSelect ?? true
            missionControlShowMissionGeofencesOnMap = loaded.missionControlShowMissionGeofencesOnMap ?? true
            missionRunResetSitlToStartPoseOnSuccessfulComplete = loaded.missionRunResetSitlToStartPoseOnSuccessfulComplete ?? false
            missionRunSimBatteryDrainRate = loaded.missionRunSimBatteryDrainRate ?? .normal
            simSpawnDefaults = loaded.simSpawnDefaults ?? .default
            callsign = loaded.callsign ?? ""
        } else {
            defaultSimulationPlatform = .ardupilot
            defaultMapTileStyle = .standard
            logRetentionProfile = .default
            appearanceMode = .system
            mainSidebarLaunchMode = .collapsed
            liveDriveSimBatteryDrainRate = .normal
            missionControlPostponeStepCapSeconds = MissionDelayPolicy.defaultOperatorPostponeStepCapSeconds
            missionControlLiveMapHideOtherTasksOnTaskSelect = true
            missionControlShowMissionGeofencesOnMap = true
            missionRunResetSitlToStartPoseOnSuccessfulComplete = false
            missionRunSimBatteryDrainRate = .normal
            simSpawnDefaults = .default
            callsign = ""
        }
    }

    private static func clampMissionPostponeStepCapSeconds(_ seconds: Int) -> Int {
        min(maxMissionPostponeStepCapSeconds, max(minMissionPostponeStepCapSeconds, seconds))
    }

    private func save() {
        let snapshot = Snapshot(
            defaultSimulationPlatform: defaultSimulationPlatform,
            defaultMapTileStyle: defaultMapTileStyle,
            logRetentionProfile: logRetentionProfile,
            appearanceMode: appearanceMode,
            mainSidebarLaunchMode: mainSidebarLaunchMode,
            liveDriveSimBatteryDrainRate: liveDriveSimBatteryDrainRate,
            defaultSimBatteryDrainRate: nil,
            missionControlPostponeStepCapSeconds: missionControlPostponeStepCapSeconds,
            missionControlLiveMapHideOtherTasksOnTaskSelect: missionControlLiveMapHideOtherTasksOnTaskSelect,
            missionControlShowMissionGeofencesOnMap: missionControlShowMissionGeofencesOnMap,
            missionRunResetSitlToStartPoseOnSuccessfulComplete: missionRunResetSitlToStartPoseOnSuccessfulComplete,
            missionRunSimBatteryDrainRate: missionRunSimBatteryDrainRate,
            simSpawnDefaults: simSpawnDefaults,
            callsign: callsign
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            persistenceUserDefaults.set(data, forKey: Self.defaultsKey)
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
        /// Omitted in older saves; treated as `.collapsed`.
        var mainSidebarLaunchMode: MainSidebarLaunchMode?
        /// Omitted in older saves; treated as `.normal` after legacy migration.
        var liveDriveSimBatteryDrainRate: SimBatteryDrainRate?
        /// Legacy persisted key (former Settings → SIMs drain). Migrated into ``liveDriveSimBatteryDrainRate`` when present; omitted on new saves.
        var defaultSimBatteryDrainRate: SimBatteryDrainRate?
        /// Omitted in older saves; treated as ``MissionDelayPolicy/defaultOperatorPostponeStepCapSeconds``.
        var missionControlPostponeStepCapSeconds: Int?
        /// Omitted in older saves; treated as `true`.
        var missionControlLiveMapHideOtherTasksOnTaskSelect: Bool?
        /// Omitted in older saves; treated as `true`. Seeds new runs’ ``MissionRunOperatorDisplaySettings/showMissionGeofencesOnMap``.
        var missionControlShowMissionGeofencesOnMap: Bool?
        /// Omitted in older saves; treated as `false`. Drives MC‑R SIM reset-on-complete (README → **SIM home reset on Mission Control run complete**).
        var missionRunResetSitlToStartPoseOnSuccessfulComplete: Bool?
        /// Omitted in older saves; treated as `.normal`. Seeds new runs’ ``MissionRunOperatorDisplaySettings/simBatteryDrainRateDuringRun``.
        var missionRunSimBatteryDrainRate: SimBatteryDrainRate?
        /// Omitted in older saves; treated as `.default`.
        var simSpawnDefaults: SimSpawnDefaults?
        /// Omitted in older saves; treated as empty string.
        var callsign: String?
    }
}

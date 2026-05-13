import Foundation

/// Per-run Mission Control operator chrome and completion side-effects.
///
/// **Seeding:** ``MissionControlStore/createRun(from:cloningMissionRunDefaultsFrom:)`` copies **Settings → Missions → Mission Run**
/// values from ``GeneralSettingsStore`` into a new ``MissionRunEnvironment`` instance. Mission Control (MCS / MC‑R) reads
/// **only** these fields for the behaviours below — not ``GeneralSettingsStore``.
struct MissionRunOperatorDisplaySettings: Equatable, Sendable {
    /// When true, MC‑R overview map limits geography to the triage-selected task; when false, the full mission stays visible.
    var isolateLiveMapToSelectedTask: Bool
    /// After a qualifying successful completion, restore bound simulation vehicles to captured start poses.
    var resetSimToStartPoseOnSuccessfulComplete: Bool
    /// SIM battery drain model while this run is **executing** (``MissionRunStatus/running``). ``SimBatteryDrainRate/none`` keeps drain disabled even while running.
    var simBatteryDrainRateDuringRun: SimBatteryDrainRate

    init(
        isolateLiveMapToSelectedTask: Bool = true,
        resetSimToStartPoseOnSuccessfulComplete: Bool = false,
        simBatteryDrainRateDuringRun: SimBatteryDrainRate = .normal
    ) {
        self.isolateLiveMapToSelectedTask = isolateLiveMapToSelectedTask
        self.resetSimToStartPoseOnSuccessfulComplete = resetSimToStartPoseOnSuccessfulComplete
        self.simBatteryDrainRateDuringRun = simBatteryDrainRateDuringRun
    }

    static let `default` = MissionRunOperatorDisplaySettings()
}

extension MissionRunOperatorDisplaySettings: Codable {
    enum CodingKeys: String, CodingKey {
        case isolateLiveMapToSelectedTask
        case resetSimToStartPoseOnSuccessfulComplete
        case simBatteryDrainRateDuringRun
        /// Legacy: optional tri-state; `nil` meant “follow app default” (approximated as `true` when migrating).
        case liveMapIsolateOnTaskSelect
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Bool.self, forKey: .isolateLiveMapToSelectedTask) {
            isolateLiveMapToSelectedTask = v
        } else if c.contains(.liveMapIsolateOnTaskSelect) {
            let legacy = try c.decodeIfPresent(Bool.self, forKey: .liveMapIsolateOnTaskSelect)
            isolateLiveMapToSelectedTask = legacy ?? true
        } else {
            isolateLiveMapToSelectedTask = true
        }
        resetSimToStartPoseOnSuccessfulComplete = try c.decodeIfPresent(
            Bool.self,
            forKey: .resetSimToStartPoseOnSuccessfulComplete
        ) ?? false
        simBatteryDrainRateDuringRun = try c.decodeIfPresent(
            SimBatteryDrainRate.self,
            forKey: .simBatteryDrainRateDuringRun
        ) ?? .normal
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isolateLiveMapToSelectedTask, forKey: .isolateLiveMapToSelectedTask)
        try c.encode(resetSimToStartPoseOnSuccessfulComplete, forKey: .resetSimToStartPoseOnSuccessfulComplete)
        try c.encode(simBatteryDrainRateDuringRun, forKey: .simBatteryDrainRateDuringRun)
    }
}

/// Maps ``MissionRunOperatorDisplaySettings/isolateLiveMapToSelectedTask`` to menu-style picks (tests / helpers).
enum MissionRunLiveMapWhenTaskSelectedPick: String, CaseIterable, Identifiable, Sendable {
    case isolateMap
    case fullMissionMap

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .isolateMap: return "Isolate map"
        case .fullMissionMap: return "Full map"
        }
    }

    var isolates: Bool { self == .isolateMap }

    static func pick(isolates: Bool) -> Self {
        isolates ? .isolateMap : .fullMissionMap
    }
}

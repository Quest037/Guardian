import Foundation

enum MissionRunStatus: String, Codable, CaseIterable, Identifiable {
    case setup
    case running
    case paused
    case completed

    var id: String { rawValue }
}

enum MissionRunScheduleMode: String, Codable, CaseIterable, Identifiable {
    case oneOff = "One-Off"
    case loop = "Loop"
    /// Legacy persisted value; decoded runs normalize to ``loop`` with `loopIntervalMinutes == 0`.
    case continuous = "Continuous"

    var id: String { rawValue }
}

/// How the run reached **completed** status (for Mission Control report).
enum MissionRunCompletionKind: String, Codable, Equatable {
    case operatorStoppedImmediate
    case operatorStoppedAfterCycle
    case oneOffAutopilotFinished
    case loopCompletedAllRepeats
}

/// Loop / continuous schedule is waiting before starting the next autopilot mission cycle.
struct MissionCycleIntermission: Equatable {
    /// When the delayed restart task is due to fire.
    let restartAt: Date
    /// Length of this wait (seconds), for progress fill.
    let totalDelay: TimeInterval
    let scheduleMode: MissionRunScheduleMode
}

/// Per-path loop delay (minutes between full autopilot cycles). **MC Setup** will edit these; when a path is absent, the run uses ``MissionRun/loopIntervalMinutes``.
struct PathLoopTiming: Codable, Equatable, Identifiable {
    var id: UUID { pathId }
    var pathId: UUID
    /// Clamped 0…59 like run-level loop delay; **0** means start the next cycle immediately for this path.
    var intervalMinutes: Int
}

/// Per-path delay (minutes) after Paladin begins execution before this path’s MAVLink mission upload/start. **0** = start with the first batch (after staging). MC Setup **Paths** tab.
struct PathStartDelay: Codable, Equatable, Identifiable {
    var id: UUID { pathId }
    var pathId: UUID
    /// Clamped 0…59; **0** is equivalent to omitting this path from the list.
    var startDelayMinutes: Int
}

/// Initial mission start for a path is waiting on `startAt` (after ``PathStartDelay``).
struct MissionPathStartDeferral: Equatable {
    let startAt: Date
    let totalDelay: TimeInterval
}

/// One-off: plan is compiled and the run is **running**, but Paladin staging / mission commands wait until `executeAt`.
struct MissionOneOffDeferredExecution: Equatable {
    let executeAt: Date
    /// When the countdown began (for progress UI).
    let countdownStartedAt: Date
}

struct MissionRunAssignment: Identifiable, Codable, Equatable {
    let id: UUID
    /// Path this slot belongs to; `nil` for legacy runs created before path grouping.
    var pathId: UUID?
    var rosterDeviceId: UUID
    var slotName: String
    var attachedDevice: String
    /// `FleetMissionVehicleToken.storageKey` when bound to the Vehicles list; `nil` if unassigned or legacy text-only.
    var attachedFleetVehicleToken: String?
    /// Optional setup-stage override for where a bound SIM should start before mission execution.
    var simStartOverrideCoord: RouteCoordinate?

    init(
        id: UUID = UUID(),
        pathId: UUID? = nil,
        rosterDeviceId: UUID,
        slotName: String,
        attachedDevice: String = "",
        attachedFleetVehicleToken: String? = nil,
        simStartOverrideCoord: RouteCoordinate? = nil
    ) {
        self.id = id
        self.pathId = pathId
        self.rosterDeviceId = rosterDeviceId
        self.slotName = slotName
        self.attachedDevice = attachedDevice
        self.attachedFleetVehicleToken = attachedFleetVehicleToken
        self.simStartOverrideCoord = simStartOverrideCoord
    }

    enum CodingKeys: String, CodingKey {
        case id, pathId, rosterDeviceId, slotName, attachedDevice, attachedFleetVehicleToken, simStartOverrideCoord
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        pathId = try c.decodeIfPresent(UUID.self, forKey: .pathId)
        rosterDeviceId = try c.decode(UUID.self, forKey: .rosterDeviceId)
        slotName = try c.decode(String.self, forKey: .slotName)
        attachedDevice = try c.decodeIfPresent(String.self, forKey: .attachedDevice) ?? ""
        attachedFleetVehicleToken = try c.decodeIfPresent(String.self, forKey: .attachedFleetVehicleToken)
        simStartOverrideCoord = try c.decodeIfPresent(RouteCoordinate.self, forKey: .simStartOverrideCoord)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(pathId, forKey: .pathId)
        try c.encode(rosterDeviceId, forKey: .rosterDeviceId)
        try c.encode(slotName, forKey: .slotName)
        try c.encode(attachedDevice, forKey: .attachedDevice)
        try c.encodeIfPresent(attachedFleetVehicleToken, forKey: .attachedFleetVehicleToken)
        try c.encodeIfPresent(simStartOverrideCoord, forKey: .simStartOverrideCoord)
    }

    /// Roster slot is ready to start when tied to a fleet vehicle or legacy free-text device.
    var hasFleetOrLegacyAssignment: Bool {
        if let t = attachedFleetVehicleToken, !t.isEmpty { return true }
        return !attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Start run preflight (arm probe UI + store)

enum MissionRunPreflightSlotPhase: String, Equatable {
    case pending
    case testing
    case passed
    case failed
}

struct MissionRunPreflightSlotRow: Identifiable, Equatable {
    let assignmentID: UUID
    let slotName: String
    var phase: MissionRunPreflightSlotPhase
    var detail: String
    /// Set when **`phase == .failed`** — operator hints from `PreflightFailureAdvisor` (pattern-matched; extend in `PreflightFailureAdvisor.swift`).
    var remediationAdvice: PreflightFailureRemediationAdvice? = nil

    var id: UUID { assignmentID }
}

/// Result of a **single-vehicle** preflight probe (Vehicles preflight modal).
struct SingleVehiclePreflightProbeResult: Equatable {
    let passed: Bool
    /// True when an arm command was sent and succeeded (vehicle likely armed); false if already armed or probe failed before arm.
    let armedDuringProbe: Bool
    let detail: String
    let remediationAdvice: PreflightFailureRemediationAdvice?
}

struct MissionRun: Identifiable, Codable, Equatable {
    let id: UUID
    var missionId: UUID
    var missionName: String
    var status: MissionRunStatus
    var scheduleMode: MissionRunScheduleMode
    /// Optional first execution time for any schedule (`nil` = start as soon as preflight succeeds). **Start Run** is blocked only if this instant is in the past (± a few seconds tolerance).
    var oneOffStartAt: Date?
    /// Minutes to wait after each full autopilot mission cycle before the next (0 = immediate next cycle). Used when the run repeats (`.loop`).
    var loopIntervalMinutes: Int
    var loopRepeatCount: Int
    /// Per-path loop spacing overrides (see ``PathLoopTiming``). Empty ⇒ all paths use ``loopIntervalMinutes``.
    var pathLoopTimings: [PathLoopTiming]
    /// Per-path delay before first MAVLink mission start (see ``PathStartDelay``). Empty ⇒ all paths start immediately after staging.
    var pathStartDelays: [PathStartDelay]
    var assignments: [MissionRunAssignment]
    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    /// When true, the run finishes the current cycle gracefully, then stops (no further loop / continuous scheduling).
    var pendingGracefulCycleStop: Bool
    /// Set when `status` becomes `.completed`: full autopilot mission cycles finished this run (loop / continuous counter; one-off uses at least 1 when autopilot finished).
    var reportAutopilotCyclesCompleted: Int?
    /// Why the run ended (operator vs autopilot schedule).
    var completionKind: MissionRunCompletionKind?

    init(
        id: UUID = UUID(),
        missionId: UUID,
        missionName: String,
        status: MissionRunStatus = .setup,
        scheduleMode: MissionRunScheduleMode = .oneOff,
        oneOffStartAt: Date? = nil,
        loopIntervalMinutes: Int = 15,
        loopRepeatCount: Int = 0,
        pathLoopTimings: [PathLoopTiming] = [],
        pathStartDelays: [PathStartDelay] = [],
        assignments: [MissionRunAssignment] = [],
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        pendingGracefulCycleStop: Bool = false,
        reportAutopilotCyclesCompleted: Int? = nil,
        completionKind: MissionRunCompletionKind? = nil
    ) {
        self.id = id
        self.missionId = missionId
        self.missionName = missionName
        self.status = status
        self.scheduleMode = scheduleMode
        self.oneOffStartAt = oneOffStartAt
        self.loopIntervalMinutes = loopIntervalMinutes
        self.loopRepeatCount = loopRepeatCount
        self.pathLoopTimings = pathLoopTimings
        self.pathStartDelays = pathStartDelays
        self.assignments = assignments
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.pendingGracefulCycleStop = pendingGracefulCycleStop
        self.reportAutopilotCyclesCompleted = reportAutopilotCyclesCompleted
        self.completionKind = completionKind
    }

    enum CodingKeys: String, CodingKey {
        case id, missionId, missionName, status, scheduleMode, oneOffStartAt, loopIntervalMinutes, loopRepeatCount
        case pathLoopTimings, pathStartDelays
        case assignments, createdAt, startedAt, completedAt, pendingGracefulCycleStop
        case reportAutopilotCyclesCompleted, completionKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        missionId = try c.decode(UUID.self, forKey: .missionId)
        missionName = try c.decode(String.self, forKey: .missionName)
        status = try c.decode(MissionRunStatus.self, forKey: .status)
        scheduleMode = try c.decode(MissionRunScheduleMode.self, forKey: .scheduleMode)
        oneOffStartAt = try c.decodeIfPresent(Date.self, forKey: .oneOffStartAt)
        loopIntervalMinutes = try c.decode(Int.self, forKey: .loopIntervalMinutes)
        loopRepeatCount = try c.decodeIfPresent(Int.self, forKey: .loopRepeatCount) ?? 0
        pathLoopTimings = try c.decodeIfPresent([PathLoopTiming].self, forKey: .pathLoopTimings) ?? []
        pathStartDelays = try c.decodeIfPresent([PathStartDelay].self, forKey: .pathStartDelays) ?? []
        // Legacy “Continuous” is now loop + 0 minute gap (immediate next cycle).
        if scheduleMode == .continuous {
            scheduleMode = .loop
            loopIntervalMinutes = 0
            loopRepeatCount = 0
        }
        assignments = try c.decode([MissionRunAssignment].self, forKey: .assignments)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        pendingGracefulCycleStop = try c.decodeIfPresent(Bool.self, forKey: .pendingGracefulCycleStop) ?? false
        reportAutopilotCyclesCompleted = try c.decodeIfPresent(Int.self, forKey: .reportAutopilotCyclesCompleted)
        completionKind = try c.decodeIfPresent(MissionRunCompletionKind.self, forKey: .completionKind)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(missionId, forKey: .missionId)
        try c.encode(missionName, forKey: .missionName)
        try c.encode(status, forKey: .status)
        try c.encode(scheduleMode, forKey: .scheduleMode)
        try c.encodeIfPresent(oneOffStartAt, forKey: .oneOffStartAt)
        try c.encode(loopIntervalMinutes, forKey: .loopIntervalMinutes)
        try c.encode(loopRepeatCount, forKey: .loopRepeatCount)
        try c.encode(pathLoopTimings, forKey: .pathLoopTimings)
        try c.encode(pathStartDelays, forKey: .pathStartDelays)
        try c.encode(assignments, forKey: .assignments)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(pendingGracefulCycleStop, forKey: .pendingGracefulCycleStop)
        try c.encodeIfPresent(reportAutopilotCyclesCompleted, forKey: .reportAutopilotCyclesCompleted)
        try c.encodeIfPresent(completionKind, forKey: .completionKind)
    }
}

extension MissionRun {
    /// Clock skew / picker granularity: within this many seconds of `referenceNow`, a scheduled time is not treated as “in the past” for disabling **Start Run**.
    static let oneOffScheduleTimeTolerance: TimeInterval = 2

    /// True when a **scheduled first start** (`oneOffStartAt`) is unrecoverably in the past (one-off or loop).
    func oneOffScheduledTimeTooFarInPast(referenceNow: Date) -> Bool {
        guard let t = oneOffStartAt else { return false }
        return t.timeIntervalSince(referenceNow) < -Self.oneOffScheduleTimeTolerance
    }

    /// Autopilot mission cycles repeat after each full cycle (vs single one-off).
    var repeatsAutopilotMissionCycles: Bool {
        scheduleMode == .loop || scheduleMode == .continuous
    }

    /// Minutes between mission cycles, clamped to the editor range. **0** means start the next cycle immediately (legacy Continuous).
    var loopDelayMinutesClamped: Int {
        min(59, max(0, loopIntervalMinutes))
    }

    /// Tight back-to-back cycles: Paladin uses threshold-driven handoff between cycles.
    var paladinTightCycleHandoff: Bool {
        repeatsAutopilotMissionCycles && (scheduleMode == .continuous || loopDelayMinutesClamped == 0)
    }

    /// Effective minutes to wait after a full cycle on **`pathId`** before the next (loop mode). Uses ``pathLoopTimings`` when present, else run-level delay.
    func loopDelayMinutes(forPath pathId: UUID) -> Int {
        if let t = pathLoopTimings.first(where: { $0.pathId == pathId }) {
            return min(59, max(0, t.intervalMinutes))
        }
        return loopDelayMinutesClamped
    }

    /// Minutes to wait after execution begins before this path’s first MAVLink mission start (0 = immediate with the first batch).
    func startDelayMinutes(forPath pathId: UUID) -> Int {
        if let t = pathStartDelays.first(where: { $0.pathId == pathId }) {
            return min(59, max(0, t.startDelayMinutes))
        }
        return 0
    }

}

extension Date {
    /// Banner copy: **on** (date) **at** (time), e.g. "Execution begins …".
    var guardianScheduleOnAtPhrase: String {
        let dateOnly = formatted(date: .abbreviated, time: .omitted)
        let timeOnly = formatted(date: .omitted, time: .shortened)
        return "on \(dateOnly) at \(timeOnly)"
    }

    /// Log / sentence copy after **until** or **to**: date then **at** time (no leading **on**).
    var guardianScheduleDateAtTimePhrase: String {
        let dateOnly = formatted(date: .abbreviated, time: .omitted)
        let timeOnly = formatted(date: .omitted, time: .shortened)
        return "\(dateOnly) at \(timeOnly)"
    }
}

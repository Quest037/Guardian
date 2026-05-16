import Foundation

enum MissionRunSessionPhase: String, Equatable {
    case draft
    case compiled
    /// Plan is ready; waiting for a scheduled execution instant (e.g. one-off future start) before staging/mission passes run.
    case staging
    /// Task force is executing its mission.
    case executing
    /// Success wind-down after execution (return to launch / recovery protocol).
    case recovery
    /// Run finished successfully (paired with ``MissionRunStatus/completed`` after operator confirms).
    case completed
    /// Abort protocol active after execution (while ``MissionRunStatus`` remains ``MissionRunStatus/running`` or ``MissionRunStatus/paused``).
    case aborting
    /// All enabled tasks have acknowledged abort, or run failed terminally (``MissionRunLifecycleSubsystem/markFailed``).
    case aborted
}

/// Per-task lifecycle label for Mission Control runtime (derived on ``MissionRunEnvironment``).
enum MissionTaskState: String, Codable, CaseIterable, Equatable, Hashable {
    /// Mission Control is sending missions to task-force aircraft (upload / staging pass to drones).
    case compiling
    /// MC considers all roster aircraft for the task to have missions loaded; awaiting start / cycle.
    case ready
    /// Task force is getting ready to execute (e.g. countdown, arming, manual prep).
    case staging
    /// Task force is executing its mission.
    case executing
    /// Between-cycle **gap** on the task rollup (repeating tasks). **v1:** Task-level MC-R chrome no longer surfaces this state — ``deriveMissionTaskState`` maps the gap to ``executing`` while end protocol is not issued; use ``MissionSquadState/between`` and roster slot ``MissionRunAssignmentSlotState/betweenCycles`` for squad- / row-scoped gaps. Retained for ``Codable`` / any legacy snapshots.
    case between
    /// Orderly wind-down after successful task completion; roster follows recovery protocol.
    case recovery
    /// Abort protocol in progress on the task force (MC-directed; aircraft confirm separately).
    case aborting
    /// Task force has finished recovery / wind-up for this task.
    case completed
    /// Abort protocol finished for this task (operator or future fleet confirmation).
    case aborted

    /// Short operator-facing title (MC-R task chip / triage banner).
    var displayTitle: String {
        switch self {
        case .compiling: return "Compiling"
        case .ready: return "Ready"
        case .staging: return "Staging"
        case .executing: return "Executing"
        case .between: return "Between"
        case .recovery: return "Recovery"
        case .aborting: return "Aborting"
        case .completed: return "Completed"
        case .aborted: return "Aborted"
        }
    }
}

/// Per-primary-squad lifecycle label (derived on ``MissionRunEnvironment``; task cards rollup from squads).
enum MissionSquadState: String, Codable, CaseIterable, Equatable, Hashable {
    case ready
    case staging
    case executing
    case between
    /// Operator held this primary squad mid-task (park) while the run remains in **executing** session phase.
    case paused
    case recovery
    case aborting
    case aborted
    case completed

    var displayTitle: String {
        switch self {
        case .ready: return "Ready"
        case .staging: return "Staging"
        case .executing: return "Executing"
        case .between: return "Between"
        case .paused: return "Paused"
        case .recovery: return "Recovery"
        case .aborting: return "Aborting"
        case .completed: return "Completed"
        case .aborted: return "Aborted"
        }
    }
}

/// Mission Control **intent** for mission-end protocol on a task — distinct from settled ``MissionTaskState``.
///
/// Set **before** fleet wind-down commands are issued (``MissionRunEnvironment/noteMissionTaskEndAttempt(_:forTaskID:)``),
/// and cleared when operator triage, §3 slot-evidence auto mission-end ack, per-task restart, or scoped orchestration reset
/// resolves that intent. **After-cycle scheduling** uses ``MissionRunEnvironment/pendingMissionTaskGracefulWindDownKindByTaskID``
/// (task-wide synchronized boundary) and ``MissionRunEnvironment/pendingMissionSquadGracefulWindDownKindByAssignmentID``
/// (one primary squad’s own cycle end) — not attempting. Published UI map: ``MissionRunEnvironment/taskAttemptingByTaskID`` (refreshed with settled state).
enum MissionTaskAttemptState: String, Equatable, Hashable, CaseIterable {
    /// MC is driving this task into **abort** mission-end protocol (fleet may still be working or may have reported failure).
    case abortMissionEnd = "abortMissionEnd"
    /// MC is driving this task into **recovery** (complete-policy) mission-end protocol.
    case recoveryMissionEnd = "recoveryMissionEnd"

    /// Short operator-facing title (MC-R / banners).
    var displayTitle: String {
        switch self {
        case .abortMissionEnd:
            return "Abort protocol in progress"
        case .recoveryMissionEnd:
            return "Recovery protocol in progress"
        }
    }
}

extension MissionTaskAttemptState: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case MissionTaskAttemptState.abortMissionEnd.rawValue, "abortWindDownIssued", "abortWindDownScheduledAfterCycle":
            self = .abortMissionEnd
        case MissionTaskAttemptState.recoveryMissionEnd.rawValue, "recoveryWindDownIssued", "recoveryWindDownScheduledAfterCycle":
            self = .recoveryMissionEnd
        default:
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown MissionTaskAttemptState raw value \(raw)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// Per-roster-slot mission orchestration progress within a run (``TaskRosterAssignmentStatesToDo.md`` §2).
///
/// Values persist on ``MissionRunAssignment/slotLifecycleLanes`` (README **Roster slot state storage** — option **(a)** on-row). Operator-facing roster chip **title** is ``displayTitle`` (**v1 UX lock**); pointer-hover / VoiceOver detail is ``rosterSlotChipHelp`` (full sentence per state; ``blockedNoVehicle`` includes the written-off distinction).
enum MissionRunAssignmentSlotState: String, Codable, CaseIterable, Equatable, Hashable {
    case idle
    case staging
    case executingMission
    case betweenCycles
    case policyAborting
    case policyCompleting
    case policySucceeded
    case policyFailed
    case blockedNoVehicle
    case notApplicableEmptySlot
    case supersededReassigned

    var displayTitle: String {
        switch self {
        case .idle: return "Idle"
        case .staging: return "Staging"
        case .executingMission: return "On mission"
        case .betweenCycles: return "Between cycles"
        case .policyAborting: return "Abort in progress"
        case .policyCompleting: return "Recovery in progress"
        case .policySucceeded: return "End protocol succeeded"
        case .policyFailed: return "End protocol failed"
        case .blockedNoVehicle: return "No vehicle bound"
        case .notApplicableEmptySlot: return "Empty slot"
        case .supersededReassigned: return "Reassigned"
        }
    }

    /// Pointer-hover / VoiceOver hint for MC-R / MCS roster slot chip (``MissionControlRosterSlotAttentionCapsule``). Chip title stays ``displayTitle`` (v1 lock).
    var rosterSlotChipHelp: String {
        switch self {
        case .idle:
            return "Slot orchestration is idle on this row — no issued policy step is active right now."
        case .staging:
            return "This roster row is staging before mission commands dispatch."
        case .executingMission:
            return "Mission commands are active on this roster binding."
        case .betweenCycles:
            return "Between mission cycles on this row — idle until the next dispatch or operator action."
        case .policyAborting:
            return "Abort policy is executing — watch fleet acks and triage until this row settles."
        case .policyCompleting:
            return "Complete or recovery policy is executing on this row — wait for fleet confirmation."
        case .policySucceeded:
            return "This roster row’s mission-end protocol finished successfully — hub evidence matches success."
        case .policyFailed:
            return "This roster row’s mission-end protocol reported a failure — open triage and check fleet responses."
        case .blockedNoVehicle:
            return "This row has no usable vehicle binding for mission policy on the roster — slot orchestration evidence. That is separate from marking a vehicle written off for this run’s floating reserve pool; written off only excludes that vehicle from pool draws and swap picks."
        case .notApplicableEmptySlot:
            return "This template row has no roster binding — it does not carry live mission policy until you assign a vehicle."
        case .supersededReassigned:
            return "This binding was replaced by a reassignment — use the active roster row for this task."
        }
    }
}

/// Per-assignment **commanded** vs **observed** slot lifecycle (``TaskRosterAssignmentStatesToDo.md`` §2 v2).
///
/// - **commanded:** last state driven by MRE dispatch / policy issuance (never updated by hub-only ticks).
/// - **observed:** hub / recipe / pull-conformance view (may lag or briefly disagree).
///
/// Use ``MissionRunAssignmentSlotLaneMerge/preferredDisplayState(lanes:)`` for UI so stale telemetry does not hide an issued abort/complete policy.
struct MissionRunAssignmentSlotStateLanes: Codable, Equatable, Hashable {
    var commanded: MissionRunAssignmentSlotState
    var observed: MissionRunAssignmentSlotState

    init(commanded: MissionRunAssignmentSlotState = .idle, observed: MissionRunAssignmentSlotState = .idle) {
        self.commanded = commanded
        self.observed = observed
    }
}

extension MissionRunAssignmentSlotState {
    /// When true, ``MissionRunAssignmentSlotLaneMerge/preferredDisplayState(lanes:)`` keeps **commanded** over **observed** so lagging hub data cannot mask an in-flight abort/complete policy.
    var prefersCommandedLaneForDisplayMerge: Bool {
        switch self {
        case .policyAborting, .policyCompleting:
            return true
        default:
            return false
        }
    }

    /// Commanded values that remain authoritative over observed updates for merge/display (terminal or non-participating).
    var isCommandedTerminalOrNonParticipatingMergeLock: Bool {
        switch self {
        case .policySucceeded, .policyFailed, .supersededReassigned, .notApplicableEmptySlot, .blockedNoVehicle:
            return true
        default:
            return false
        }
    }

    /// Mission Control roster / live-console chip severity. `nil` means **no pill** (quiet default lanes).
    var missionControlRosterBadgeSeverity: GuardianFeedbackSeverity? {
        switch self {
        case .idle, .notApplicableEmptySlot:
            return nil
        case .staging, .executingMission, .betweenCycles, .supersededReassigned, .policyCompleting:
            return .info
        case .policyAborting:
            return .warning
        case .policySucceeded:
            return .success
        case .policyFailed, .blockedNoVehicle:
            return .error
        }
    }
}

/// Resolves **commanded** vs **observed** ``MissionRunAssignmentSlotState`` for a single display label.
enum MissionRunAssignmentSlotLaneMerge {
    /// Picks one ``MissionRunAssignmentSlotState`` for chips / Paladin / rollup when the two lanes disagree.
    ///
    /// **Rules (v1):** (1) If **commanded** is ``policyAborting`` / ``policyCompleting``, return **commanded**. (2) If **commanded** is terminal or slot-non-participating (see ``MissionRunAssignmentSlotState/isCommandedTerminalOrNonParticipatingMergeLock``), return **commanded**. (3) If **observed** reports ``policyFailed`` or ``blockedNoVehicle`` while **commanded** is still ``idle`` / ``staging`` / ``executingMission`` / ``betweenCycles``, return **observed** so evidence-backed failures surface. (4) Otherwise return **commanded**.
    ///
    /// Extend when §3 evidence catalogue adds richer pull-path semantics.
    static func preferredDisplayState(lanes: MissionRunAssignmentSlotStateLanes) -> MissionRunAssignmentSlotState {
        let c = lanes.commanded
        let o = lanes.observed
        if c.prefersCommandedLaneForDisplayMerge || c.isCommandedTerminalOrNonParticipatingMergeLock {
            return c
        }
        switch o {
        case .policyFailed, .blockedNoVehicle:
            switch c {
            case .idle, .staging, .executingMission, .betweenCycles:
                return o
            default:
                break
            }
        default:
            break
        }
        return c
    }
}

/// Roll-up helpers for MC-R task rows (worst slot attention across bound roster rows).
enum MissionControlAssignmentSlotRosterAttention {
    /// Picks the highest-precedence ``GuardianFeedbackSeverity`` among assignments’ merged slot states (for a compact task-row chip).
    static func worstAmong(assignments: [MissionRunAssignment]) -> (severity: GuardianFeedbackSeverity, title: String, help: String)? {
        worstAmongImpl(assignments: assignments, skipBetweenCyclesForTaskRow: false)
    }

    /// Same ranking as ``worstAmong`` but **drops** ``MissionRunAssignmentSlotState/betweenCycles`` rows — between-cycle orchestration is squad/roster scoped; the MC-R **Tasks** card task header should not duplicate that as a second pill while the task rollup reads **Executing**.
    static func worstAmongForTaskRow(assignments: [MissionRunAssignment]) -> (severity: GuardianFeedbackSeverity, title: String, help: String)? {
        worstAmongImpl(assignments: assignments, skipBetweenCyclesForTaskRow: true)
    }

    private static func worstAmongImpl(
        assignments: [MissionRunAssignment],
        skipBetweenCyclesForTaskRow: Bool
    ) -> (severity: GuardianFeedbackSeverity, title: String, help: String)? {
        var bestRank = -1
        var picked: (GuardianFeedbackSeverity, String, String)?
        for a in assignments {
            let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: a.effectiveSlotLifecycleLanes)
            if skipBetweenCyclesForTaskRow, merged == .betweenCycles { continue }
            guard let sev = merged.missionControlRosterBadgeSeverity else { continue }
            let r = rank(sev)
            if r > bestRank {
                bestRank = r
                picked = (sev, merged.displayTitle, merged.rosterSlotChipHelp)
            }
        }
        return picked
    }

    private static func rank(_ s: GuardianFeedbackSeverity) -> Int {
        switch s {
        case .error: return 3
        case .warning: return 2
        case .success: return 1
        case .info: return 0
        }
    }
}

enum MissionRunStatus: String, Codable, CaseIterable, Identifiable {
    case setup
    case running
    case paused
    case recovery
    case completed

    var id: String { rawValue }

    /// When true, Mission Control applies this run’s per-run SIM battery drain rate to roster SITL streams (see ``MissionControlSetupView/syncSimBatteryDrainForRunStatus``).
    var appliesMissionRunSimBatteryDrainFromOperatorSettings: Bool {
        self == .running || self == .recovery
    }
}

/// How the run reached **completed** status (for Mission Control report).
enum MissionRunCompletionKind: String, Codable, Equatable {
    case operatorStoppedImmediate
    case operatorStoppedAfterCycle
    /// Operator ended the run for orderly recovery (return to launch / home), not using abort policy.
    case operatorCompletedImmediate
    case operatorCompletedAfterCycle
    case oneOffAutopilotFinished
}

extension MissionRunCompletionKind {
    /// Policy for optional **SIM start-pose restore** after a Mission Control run (see README → SIM home reset on Mission Control run complete).
    ///
    /// Only **complete** / autopilot-finished outcomes qualify; **stop** outcomes do not. A missing stored kind is treated as ineligible at the call site.
    var qualifiesForSimHomeRestoreAfterSuccessfulMissionRun: Bool {
        switch self {
        case .operatorCompletedImmediate, .operatorCompletedAfterCycle, .oneOffAutopilotFinished:
            return true
        case .operatorStoppedImmediate, .operatorStoppedAfterCycle:
            return false
        }
    }
}

/// Queued “finish after this autopilot mission cycle” intent: **abort** uses abort-policy commands; **complete** uses recovery RTL wind-down.
enum MissionRunGracefulStopKind: String, Codable, Equatable {
    case none
    case abortAfterCycle
    case completeAfterCycle
}

/// Fleet-command scope for Mission Control orchestration (task today; squad / single slot later).
enum MissionRunCommandTarget: Equatable, Hashable, Sendable {
    case task(UUID)
    /// One primary squad (``MissionRunAssignment/id`` for the primary roster row).
    case squad(primaryAssignmentID: UUID)
}

/// Per-task “after this autopilot mission cycle” wind-down (does not use whole-run ``MissionRunGracefulStopKind``).
enum MissionRunMissionTaskGracefulPendingKind: String, Codable, Equatable {
    case abortAfterCycle
    case completeAfterCycle
}

// MARK: - Abort (scheduling → planner → fleet commands)

/// Autopilot-facing action when a run aborts (resolved **assignment → task → mission** via ``MissionRunPolicyResolution``).
enum MissionRunAbortPolicy: String, Equatable, CaseIterable, Identifiable, Codable {
    case returnToLaunch
    case loiter
    /// Do not issue an autopilot command from policy alone (run teardown may still occur elsewhere).
    case none

    var id: String { rawValue }

    /// MC Setup **Rules** tab menu labels.
    var setupMenuLabel: String {
        switch self {
        case .returnToLaunch: return "Return to Launch"
        case .loiter: return "Loiter"
        case .none: return "None"
        }
    }

    /// MC Setup **Rules** abort dropdown ordering (**Return to Launch** first; includes all planner-backed values).
    static var setupPickerCases: [MissionRunAbortPolicy] {
        [.returnToLaunch, .loiter, .none]
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        switch raw {
        case "holdPosition": self = .loiter
        case "land": self = .returnToLaunch
        default:
            guard let v = Self(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: c,
                    debugDescription: "Unknown MissionRunAbortPolicy raw value: \(raw)"
                )
            }
            self = v
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Abort preference chain (ordered tactics)

/// One step in an **ordered** abort preference chain. Mission Control walks the chain **optimistically**
/// (first tactic that can be planned wins). Chains should **end with** ``Kind/park`` so a vehicle that
/// cannot satisfy earlier tactics still receives a safe park / rescue posture.
struct MissionRunAbortTactic: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case returnToLaunch
        /// Autopilot hold / loiter (``FleetVehicleCommand/holdPosition``).
        case loiter
        case park
        /// Nearest **open** ``MissionPoint`` of ``mapPointKind`` (task-scoped or mission-wide), then park via the move-point-park recipe.
        case nearestOpenMapPoint
    }

    var id: UUID
    var kind: Kind
    /// Meaningful when ``kind == nearestOpenMapPoint`` (defaults to ``MissionPointKind/rally`` when absent).
    var mapPointKind: MissionPointKind?

    init(id: UUID = UUID(), kind: Kind, mapPointKind: MissionPointKind? = nil) {
        self.id = id
        self.kind = kind
        self.mapPointKind = mapPointKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, mapPointKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawKind = try c.decode(String.self, forKey: .kind)
        kind = Kind(migratedFromStoredRaw: rawKind)
        mapPointKind = try c.decodeIfPresent(MissionPointKind.self, forKey: .mapPointKind)
        if kind == .nearestOpenMapPoint, mapPointKind == nil {
            mapPointKind = .rally
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        if kind == .nearestOpenMapPoint {
            try c.encode(mapPointKind ?? .rally, forKey: .mapPointKind)
        } else {
            try c.encodeIfPresent(mapPointKind, forKey: .mapPointKind)
        }
    }

    /// Row labels for tactic pickers and policy editors.
    var setupMenuLabel: String {
        switch kind {
        case .returnToLaunch: return "Return to Launch"
        case .loiter: return "Loiter"
        case .park: return "Park"
        case .nearestOpenMapPoint:
            return "Nearest open mission point"
        }
    }

    /// Default mission-wide chain: try a rally move+parking pass, then RTL, then class-aware park.
    static let defaultMissionAbortPreferenceChain: [MissionRunAbortTactic] = [
        MissionRunAbortTactic(kind: .nearestOpenMapPoint, mapPointKind: .rally),
        MissionRunAbortTactic(kind: .returnToLaunch),
        MissionRunAbortTactic(kind: .park),
    ]

    /// Stable ordering for “Add tactic” menus (park intentionally last in the menu; operators may reorder after adding).
    static var addMenuKindOrdering: [Kind] {
        [.nearestOpenMapPoint, .returnToLaunch, .loiter, .park]
    }

    /// Ensures ``mapPointKind`` is set for map-point tactics and that a non-empty chain **ends** with ``Kind/park``.
    static func normalizedPreferenceChain(_ tactics: [MissionRunAbortTactic]) -> [MissionRunAbortTactic] {
        var rows = tactics
        for i in rows.indices {
            if rows[i].kind == .nearestOpenMapPoint, rows[i].mapPointKind == nil {
                rows[i].mapPointKind = .rally
            }
        }
        if rows.isEmpty {
            return defaultMissionAbortPreferenceChain
        }
        if rows.last?.kind != .park {
            rows.append(MissionRunAbortTactic(kind: .park))
        }
        return rows
    }

    /// Fresh row ids so template edits do not share identities with inherited snapshots.
    static func copyingForIndependentEdit(_ tactics: [MissionRunAbortTactic]) -> [MissionRunAbortTactic] {
        tactics.map { MissionRunAbortTactic(id: UUID(), kind: $0.kind, mapPointKind: $0.mapPointKind) }
    }

    static func summarizedForLogging(_ tactics: [MissionRunAbortTactic]) -> String {
        tactics.map(\.setupMenuLabel).joined(separator: " → ")
    }
}

private extension MissionRunAbortTactic.Kind {
    /// Older JSON used ``holdPosition`` / ``land``; map to current kinds on decode.
    init(migratedFromStoredRaw raw: String) {
        switch raw {
        case "holdPosition": self = .loiter
        case "land": self = .returnToLaunch
        default: self = Self(rawValue: raw) ?? .returnToLaunch
        }
    }
}

// MARK: - Complete preference chain (ordered tactics)

/// One step in an **ordered** complete (recovery) preference chain. Mission Control walks the chain **optimistically**
/// (first tactic that can be planned wins). Chains normally **end with** ``Kind/park``; a lone ``Kind/none`` means no
/// automatic wind-down command is issued.
struct MissionRunCompleteTactic: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case returnToLaunch
        /// Autopilot hold / loiter (``FleetVehicleCommand/holdPosition``).
        case loiter
        case park
        case nearestOpenMapPoint
        /// Skip without issuing; if it is the only tactic, no wind-down command is sent.
        case none
    }

    var id: UUID
    var kind: Kind
    var mapPointKind: MissionPointKind?

    init(id: UUID = UUID(), kind: Kind, mapPointKind: MissionPointKind? = nil) {
        self.id = id
        self.kind = kind
        self.mapPointKind = mapPointKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, mapPointKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawKind = try c.decode(String.self, forKey: .kind)
        kind = Kind(migratedFromStoredRaw: rawKind)
        mapPointKind = try c.decodeIfPresent(MissionPointKind.self, forKey: .mapPointKind)
        if kind == .nearestOpenMapPoint, mapPointKind == nil {
            mapPointKind = .rally
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        if kind == .nearestOpenMapPoint {
            try c.encode(mapPointKind ?? .rally, forKey: .mapPointKind)
        } else {
            try c.encodeIfPresent(mapPointKind, forKey: .mapPointKind)
        }
    }

    var setupMenuLabel: String {
        switch kind {
        case .returnToLaunch: return "Return to Launch"
        case .loiter: return "Loiter"
        case .park: return "Park"
        case .nearestOpenMapPoint: return "Nearest open mission point"
        case .none: return "None"
        }
    }

    static let defaultMissionCompletePreferenceChain: [MissionRunCompleteTactic] = [
        MissionRunCompleteTactic(kind: .returnToLaunch),
        MissionRunCompleteTactic(kind: .park),
    ]

    static var addMenuKindOrdering: [Kind] {
        [.nearestOpenMapPoint, .returnToLaunch, .loiter, .none, .park]
    }

    static func normalizedPreferenceChain(_ tactics: [MissionRunCompleteTactic]) -> [MissionRunCompleteTactic] {
        var rows = tactics
        for i in rows.indices {
            if rows[i].kind == .nearestOpenMapPoint, rows[i].mapPointKind == nil {
                rows[i].mapPointKind = .rally
            }
        }
        if rows.isEmpty {
            return defaultMissionCompletePreferenceChain
        }
        if rows.count == 1, rows[0].kind == .none {
            return rows
        }
        if rows.last?.kind != .park {
            rows.append(MissionRunCompleteTactic(kind: .park))
        }
        return rows
    }

    static func copyingForIndependentEdit(_ tactics: [MissionRunCompleteTactic]) -> [MissionRunCompleteTactic] {
        tactics.map { MissionRunCompleteTactic(id: UUID(), kind: $0.kind, mapPointKind: $0.mapPointKind) }
    }

    static func summarizedForLogging(_ tactics: [MissionRunCompleteTactic]) -> String {
        tactics.map(\.setupMenuLabel).joined(separator: " → ")
    }
}

private extension MissionRunCompleteTactic.Kind {
    /// Older JSON used ``holdPosition`` / ``land``; map to current kinds on decode.
    init(migratedFromStoredRaw raw: String) {
        switch raw {
        case "holdPosition": self = .loiter
        case "land": self = .returnToLaunch
        default: self = Self(rawValue: raw) ?? .returnToLaunch
        }
    }
}

// MARK: - Reserve swap preference chain (displaced active wind-down)

/// One step in an **ordered** **reserve swap** preference chain: after a successful pool or fixed-reserve swap-in commit,
/// the **post-commit** row that still owns the displaced aircraft (pool berth or bench ``.reserve``) uses this chain to
/// choose RTL / rally / loiter / park (same catalogue shapes as complete recovery — see ``MissionRunFleetDispatch/preferentialReserveSwapTacticDispatch``).
///
/// Resolution precedence matches abort/complete: **assignment → task → mission** (``MissionRunPolicyResolution``).
struct MissionRunReserveSwapTactic: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case returnToLaunch
        case loiter
        case park
        case nearestOpenMapPoint
        case none
    }

    var id: UUID
    var kind: Kind
    var mapPointKind: MissionPointKind?

    init(id: UUID = UUID(), kind: Kind, mapPointKind: MissionPointKind? = nil) {
        self.id = id
        self.kind = kind
        self.mapPointKind = mapPointKind
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, mapPointKind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let rawKind = try c.decode(String.self, forKey: .kind)
        kind = Kind(migratedFromStoredRaw: rawKind)
        mapPointKind = try c.decodeIfPresent(MissionPointKind.self, forKey: .mapPointKind)
        if kind == .nearestOpenMapPoint, mapPointKind == nil {
            mapPointKind = .rally
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        if kind == .nearestOpenMapPoint {
            try c.encode(mapPointKind ?? .rally, forKey: .mapPointKind)
        } else {
            try c.encodeIfPresent(mapPointKind, forKey: .mapPointKind)
        }
    }

    var setupMenuLabel: String {
        switch kind {
        case .returnToLaunch: return "Return to Launch"
        case .loiter: return "Loiter"
        case .park: return "Park"
        case .nearestOpenMapPoint: return "Nearest open mission point"
        case .none: return "None"
        }
    }

    /// Default mission-wide chain for displaced-active wind-down (matches ``MissionRunCompleteTactic/defaultMissionCompletePreferenceChain`` intent).
    static let defaultMissionReserveSwapPreferenceChain: [MissionRunReserveSwapTactic] = [
        MissionRunReserveSwapTactic(kind: .returnToLaunch),
        MissionRunReserveSwapTactic(kind: .park),
    ]

    static var addMenuKindOrdering: [Kind] {
        [.nearestOpenMapPoint, .returnToLaunch, .loiter, .none, .park]
    }

    static func normalizedPreferenceChain(_ tactics: [MissionRunReserveSwapTactic]) -> [MissionRunReserveSwapTactic] {
        var rows = tactics
        for i in rows.indices {
            if rows[i].kind == .nearestOpenMapPoint, rows[i].mapPointKind == nil {
                rows[i].mapPointKind = .rally
            }
        }
        if rows.isEmpty {
            return defaultMissionReserveSwapPreferenceChain
        }
        if rows.count == 1, rows[0].kind == .none {
            return rows
        }
        if rows.last?.kind != .park {
            rows.append(MissionRunReserveSwapTactic(kind: .park))
        }
        return rows
    }

    static func copyingForIndependentEdit(_ tactics: [MissionRunReserveSwapTactic]) -> [MissionRunReserveSwapTactic] {
        tactics.map { MissionRunReserveSwapTactic(id: UUID(), kind: $0.kind, mapPointKind: $0.mapPointKind) }
    }

    static func summarizedForLogging(_ tactics: [MissionRunReserveSwapTactic]) -> String {
        tactics.map(\.setupMenuLabel).joined(separator: " → ")
    }
}

private extension MissionRunReserveSwapTactic.Kind {
    init(migratedFromStoredRaw raw: String) {
        switch raw {
        case "holdPosition": self = .loiter
        case "land": self = .returnToLaunch
        default: self = Self(rawValue: raw) ?? .returnToLaunch
        }
    }
}

// MARK: - Rules of engagement (run-level; not part of compiled plan)

enum MissionRunEngagementAction: String, Codable, CaseIterable, Equatable, Hashable {
    case rtl
    case land
    case forceDisarm
    case swapInReserve
}

enum MissionRunEngagementDisposition: String, Codable, CaseIterable, Equatable, Hashable {
    case autonomous
    case ask
    case `defer`
    case forbidden
    case handoff
}

struct MissionRunEngagementRule: Codable, Equatable {
    var disposition: MissionRunEngagementDisposition

    init(disposition: MissionRunEngagementDisposition) {
        self.disposition = disposition
    }

    private enum CodingKeys: String, CodingKey {
        case disposition
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disposition = try c.decode(MissionRunEngagementDisposition.self, forKey: .disposition)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(disposition, forKey: .disposition)
    }
}

struct MissionRunEngagementRules: Codable, Equatable {
    var perAction: [MissionRunEngagementAction: MissionRunEngagementRule]

    init(perAction: [MissionRunEngagementAction: MissionRunEngagementRule] = [:]) {
        self.perAction = perAction
    }

    static let `default` = MissionRunEngagementRules()
}

/// Run-level policy bundle for ``MissionRunEnvironment`` (engagement + run geofence augmentation; abort / complete / reserve-swap chains live on ``Mission`` / ``MissionTask`` / ``MissionRunAssignmentPolicies``).
struct MissionRunPolicies: Equatable {
    var engagement: MissionRunEngagementRules
    /// **Additional** geofences for this run merged **after** all template fences for **every** task (see ``MissionRunGeofencePolicyResolution``).
    var missionGeofenceAugmentation: [MissionGeofence]

    init(engagement: MissionRunEngagementRules = .default, missionGeofenceAugmentation: [MissionGeofence] = []) {
        self.engagement = engagement
        self.missionGeofenceAugmentation = missionGeofenceAugmentation
    }
}

/// Per-assignment policy overrides. Non-`nil` values override the owning task’s policy, which overrides the mission default.
struct MissionRunAssignmentPolicies: Codable, Equatable {
    /// When non-empty, replaces the resolved **abort preference chain** for this slot (see ``MissionRunPolicyResolution``).
    var abortPreferenceChain: [MissionRunAbortTactic]?
    /// When non-empty, replaces the resolved **complete (recovery) preference chain** for this slot.
    var completePreferenceChain: [MissionRunCompleteTactic]?
    /// When non-empty, replaces the resolved **reserve swap (displaced active) preference chain** for this slot.
    var reserveSwapPreferenceChain: [MissionRunReserveSwapTactic]?
    /// **Additional** geofences for this slot merged **after** task-level planning fences (``MissionRunGeofencePolicyResolution``).
    var geofenceAugmentation: [MissionGeofence]

    init(
        abortPreferenceChain: [MissionRunAbortTactic]? = nil,
        completePreferenceChain: [MissionRunCompleteTactic]? = nil,
        reserveSwapPreferenceChain: [MissionRunReserveSwapTactic]? = nil,
        geofenceAugmentation: [MissionGeofence] = []
    ) {
        self.abortPreferenceChain = abortPreferenceChain
        self.completePreferenceChain = completePreferenceChain
        self.reserveSwapPreferenceChain = reserveSwapPreferenceChain
        self.geofenceAugmentation = geofenceAugmentation
    }

    enum CodingKeys: String, CodingKey {
        case abortPreferenceChain, completePreferenceChain, reserveSwapPreferenceChain, geofenceAugmentation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        abortPreferenceChain = try c.decodeIfPresent([MissionRunAbortTactic].self, forKey: .abortPreferenceChain)
        completePreferenceChain = try c.decodeIfPresent([MissionRunCompleteTactic].self, forKey: .completePreferenceChain)
        reserveSwapPreferenceChain = try c.decodeIfPresent([MissionRunReserveSwapTactic].self, forKey: .reserveSwapPreferenceChain)
        geofenceAugmentation = try c.decodeIfPresent([MissionGeofence].self, forKey: .geofenceAugmentation) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(abortPreferenceChain, forKey: .abortPreferenceChain)
        try c.encodeIfPresent(completePreferenceChain, forKey: .completePreferenceChain)
        try c.encodeIfPresent(reserveSwapPreferenceChain, forKey: .reserveSwapPreferenceChain)
        if !geofenceAugmentation.isEmpty {
            try c.encode(geofenceAugmentation, forKey: .geofenceAugmentation)
        }
    }
}

/// Resolves abort / complete / reserve-swap preference chains for a roster slot: **assignment → task → mission** (most specific wins).
enum MissionRunPolicyResolution {
    /// Effective task id for an assignment (explicit ``MissionRunAssignment/taskId``, or single enabled task when unambiguous).
    static func resolvedTaskId(for assignment: MissionRunAssignment, mission: Mission?) -> UUID? {
        if let taskId = assignment.taskId { return taskId }
        guard let mission else { return nil }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1 { return enabled[0].id }
        return nil
    }

    /// Effective ordered abort tactics: **assignment → task → mission** (first non-empty wins), then normalized.
    static func resolvedAbortPreferenceChain(assignment: MissionRunAssignment, mission: Mission?) -> [MissionRunAbortTactic] {
        if let slot = assignment.policies.abortPreferenceChain, !slot.isEmpty {
            return MissionRunAbortTactic.normalizedPreferenceChain(slot)
        }
        if let mission,
           let tid = resolvedTaskId(for: assignment, mission: mission),
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }),
           let override = task.abortPreferenceChainOverride,
           !override.isEmpty {
            return MissionRunAbortTactic.normalizedPreferenceChain(override)
        }
        return MissionRunAbortTactic.normalizedPreferenceChain(mission?.routeMacro.rules.missionAbortPreferenceChain ?? [])
    }

    /// Mission template default only (ignores task and assignment overrides) — for “inherited” hints in editors.
    static func missionTemplateAbortPreferenceChain(mission: Mission?) -> [MissionRunAbortTactic] {
        MissionRunAbortTactic.normalizedPreferenceChain(mission?.routeMacro.rules.missionAbortPreferenceChain ?? [])
    }

    /// Chain this slot would use if its assignment-level abort override were cleared.
    static func inheritedAbortPreferenceChainForSlot(assignment: MissionRunAssignment, mission: Mission?) -> [MissionRunAbortTactic] {
        var copy = assignment
        copy.policies.abortPreferenceChain = nil
        return resolvedAbortPreferenceChain(assignment: copy, mission: mission)
    }

    /// Effective ordered complete tactics: **assignment → task → mission** (first non-empty wins), then normalized.
    static func resolvedCompletePreferenceChain(assignment: MissionRunAssignment, mission: Mission?) -> [MissionRunCompleteTactic] {
        if let slot = assignment.policies.completePreferenceChain, !slot.isEmpty {
            return MissionRunCompleteTactic.normalizedPreferenceChain(slot)
        }
        if let mission,
           let tid = resolvedTaskId(for: assignment, mission: mission),
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }),
           let override = task.completePreferenceChainOverride,
           !override.isEmpty {
            return MissionRunCompleteTactic.normalizedPreferenceChain(override)
        }
        return MissionRunCompleteTactic.normalizedPreferenceChain(mission?.routeMacro.rules.missionCompletePreferenceChain ?? [])
    }

    static func missionTemplateCompletePreferenceChain(mission: Mission?) -> [MissionRunCompleteTactic] {
        MissionRunCompleteTactic.normalizedPreferenceChain(mission?.routeMacro.rules.missionCompletePreferenceChain ?? [])
    }

    static func inheritedCompletePreferenceChainForSlot(assignment: MissionRunAssignment, mission: Mission?) -> [MissionRunCompleteTactic] {
        var copy = assignment
        copy.policies.completePreferenceChain = nil
        return resolvedCompletePreferenceChain(assignment: copy, mission: mission)
    }

    /// Effective ordered reserve-swap tactics: **assignment → task → mission** (first non-empty wins), then normalized.
    static func resolvedReserveSwapPreferenceChain(assignment: MissionRunAssignment, mission: Mission?) -> [MissionRunReserveSwapTactic] {
        if let slot = assignment.policies.reserveSwapPreferenceChain, !slot.isEmpty {
            return MissionRunReserveSwapTactic.normalizedPreferenceChain(slot)
        }
        if let mission,
           let tid = resolvedTaskId(for: assignment, mission: mission),
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }),
           let override = task.reserveSwapPreferenceChainOverride,
           !override.isEmpty {
            return MissionRunReserveSwapTactic.normalizedPreferenceChain(override)
        }
        return MissionRunReserveSwapTactic.normalizedPreferenceChain(
            mission?.routeMacro.rules.missionReserveSwapPreferenceChain ?? []
        )
    }

    static func missionTemplateReserveSwapPreferenceChain(mission: Mission?) -> [MissionRunReserveSwapTactic] {
        MissionRunReserveSwapTactic.normalizedPreferenceChain(mission?.routeMacro.rules.missionReserveSwapPreferenceChain ?? [])
    }

    static func inheritedReserveSwapPreferenceChainForSlot(assignment: MissionRunAssignment, mission: Mission?) -> [MissionRunReserveSwapTactic] {
        var copy = assignment
        copy.policies.reserveSwapPreferenceChain = nil
        return resolvedReserveSwapPreferenceChain(assignment: copy, mission: mission)
    }
}

// MARK: - Geofence policy resolution (MRE)

/// Merges **mission template** geofences with **run-only augmentations** for planning and per-squad MAVLink builds.
///
/// **v1 product lock — additive only:** each stage appends; there is no “replace template fences” override.
/// Order: template (`Mission.missionGeofences` + `MissionTask.geofences`) → ``MissionRunPolicies/missionGeofenceAugmentation``
/// → ``MissionRunEnvironment/taskGeofenceAugmentationsByTaskID`` → ``MissionRunAssignmentPolicies/geofenceAugmentation`` (squad path only).
enum MissionRunGeofencePolicyResolution {
    /// Geofences attached to a task row in ``MissionControlPlan`` / map previews for that task (no per-slot augmentation).
    static func planningGeofences(
        taskID: UUID,
        mission: Mission,
        missionWideRunAugmentation: [MissionGeofence],
        perTaskRunAugmentation: [MissionGeofence]
    ) -> [MissionGeofence] {
        let base = MissionTemplateGeofenceUtilities().effectiveTemplateGeofencesForPlanning(taskID: taskID, mission: mission)
        return base + missionWideRunAugmentation + perTaskRunAugmentation
    }

    /// Full fence list for one primary squad’s MAVLink plan row (planning fences + this slot’s augmentation).
    static func squadGeofences(
        primaryAssignment: MissionRunAssignment,
        mission: Mission,
        missionWideRunAugmentation: [MissionGeofence],
        perTaskRunAugmentationByTaskID: [UUID: [MissionGeofence]]
    ) -> [MissionGeofence] {
        guard let tid = MissionRunPolicyResolution.resolvedTaskId(for: primaryAssignment, mission: mission) else {
            return missionWideRunAugmentation + primaryAssignment.policies.geofenceAugmentation
        }
        let taskAug = perTaskRunAugmentationByTaskID[tid] ?? []
        return planningGeofences(
            taskID: tid,
            mission: mission,
            missionWideRunAugmentation: missionWideRunAugmentation,
            perTaskRunAugmentation: taskAug
        ) + primaryAssignment.policies.geofenceAugmentation
    }

    static func summarizedFenceIDsForLogging(_ fences: [MissionGeofence]) -> String {
        if fences.isEmpty { return "none" }
        return fences.map(\.id.uuidString).joined(separator: ",")
    }
}

extension MissionRunEnvironment {
    /// ID-only signature so Mission Control maps rebuild geofence layers when **run-only** augmentation changes
    /// (independent of template ``Mission/missionGeofenceTemplateTopologySignature()`` and hub telemetry).
    func missionControlRunGeofenceAugmentationTopologySignature() -> String {
        let m = policies.missionGeofenceAugmentation.map(\.id.uuidString).sorted().joined(separator: ",")
        let t = taskGeofenceAugmentationsByTaskID.keys
            .sorted(by: { $0.uuidString < $1.uuidString })
            .map { tid in
                let ids = (taskGeofenceAugmentationsByTaskID[tid] ?? []).map(\.id.uuidString).sorted().joined(separator: ",")
                return "\(tid.uuidString)=\(ids)"
            }
            .joined(separator: ";")
        let s = assignments
            .map { asn in
                let ids = asn.policies.geofenceAugmentation.map(\.id.uuidString).sorted().joined(separator: ",")
                return "\(asn.id.uuidString)=\(ids)"
            }
            .sorted()
            .joined(separator: "|")
        return "m:\(m)|t:\(t)|s:\(s)"
    }
}

/// What triggered building an abort plan (for logging / future execution).
enum MissionRunAbortTrigger: String, Equatable {
    case now
    case afterCycle
}

/// Per-run override after Paladin begins execution before this task’s MAVLink mission upload/start (same value+unit model as ``MissionTask``). When absent, the mission template applies. MC Setup **Timing** tab **Tasks** card.
struct TaskStartDelay: Codable, Equatable, Identifiable {
    var id: UUID { taskId }
    var taskId: UUID
    var startDelayValue: Double
    var startDelayUnit: DelayUnit

    var totalSeconds: TimeInterval {
        MissionDelayPolicy.clampTotalSeconds(
            MissionDelayPolicy.totalSeconds(value: startDelayValue, unit: startDelayUnit),
            minimumTotalSeconds: 0
        )
    }

    enum CodingKeys: String, CodingKey {
        case taskId
        case legacyJSONTaskUUID = "pathId"
        case startDelayValue
        case startDelayUnit
        case legacyStartDelayMinutes = "startDelayMinutes"
    }

    init(taskId: UUID, startDelayValue: Double, startDelayUnit: DelayUnit) {
        self.taskId = taskId
        let n = MissionDelayPolicy.normalizedTaskStart(value: startDelayValue, unit: startDelayUnit)
        self.startDelayValue = n.0
        self.startDelayUnit = n.1
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try c.decodeIfPresent(UUID.self, forKey: .taskId)
            ?? c.decodeIfPresent(UUID.self, forKey: .legacyJSONTaskUUID)
            ?? UUID()
        let rawValue: Double
        let rawUnit: DelayUnit
        if let v = try c.decodeIfPresent(Double.self, forKey: .startDelayValue),
           let u = try c.decodeIfPresent(DelayUnit.self, forKey: .startDelayUnit) {
            rawValue = v
            rawUnit = u
        } else {
            let legacyMins = try c.decodeIfPresent(Int.self, forKey: .legacyStartDelayMinutes) ?? 0
            rawValue = Double(legacyMins)
            rawUnit = .mins
        }
        let n = MissionDelayPolicy.normalizedTaskStart(value: rawValue, unit: rawUnit)
        startDelayValue = n.0
        startDelayUnit = n.1
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(taskId, forKey: .taskId)
        try c.encode(startDelayValue, forKey: .startDelayValue)
        try c.encode(startDelayUnit, forKey: .startDelayUnit)
    }
}

/// Initial mission start for a path is waiting on `startAt` (after ``TaskStartDelay``).
struct MissionTaskStartDeferral: Equatable {
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
    /// Mission task this slot belongs to; `nil` for legacy runs created before task grouping.
    var taskId: UUID?
    var rosterDeviceId: UUID
    var slotName: String
    var attachedDevice: String
    /// `FleetMissionVehicleToken.storageKey` when bound to the Vehicles list; `nil` if unassigned or legacy text-only.
    var attachedFleetVehicleToken: String?
    var policies: MissionRunAssignmentPolicies
    /// Per-slot **commanded** vs **observed** lifecycle (``MissionRunAssignmentSlotStateLanes``). **Omitted** in legacy JSON and when never persisted — use ``effectiveSlotLifecycleLanes``. **Storage:** persisted slot evidence stays on this row (README **Roster slot state storage** — option **(a)** locked); ``MissionRunAssignment/syntheticForReservePool`` leaves this nil.
    var slotLifecycleLanes: MissionRunAssignmentSlotStateLanes?

    init(
        id: UUID = UUID(),
        taskId: UUID? = nil,
        rosterDeviceId: UUID,
        slotName: String,
        attachedDevice: String = "",
        attachedFleetVehicleToken: String? = nil,
        policies: MissionRunAssignmentPolicies = MissionRunAssignmentPolicies(),
        slotLifecycleLanes: MissionRunAssignmentSlotStateLanes? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.rosterDeviceId = rosterDeviceId
        self.slotName = slotName
        self.attachedDevice = attachedDevice
        self.attachedFleetVehicleToken = attachedFleetVehicleToken
        self.policies = policies
        self.slotLifecycleLanes = slotLifecycleLanes
    }

    enum CodingKeys: String, CodingKey {
        case id, taskId, legacyAssignmentTaskUUID = "pathId", rosterDeviceId, slotName, attachedDevice, attachedFleetVehicleToken
        case policies
        case slotLifecycleLanes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        taskId = try c.decodeIfPresent(UUID.self, forKey: .taskId)
            ?? c.decodeIfPresent(UUID.self, forKey: .legacyAssignmentTaskUUID)
        rosterDeviceId = try c.decode(UUID.self, forKey: .rosterDeviceId)
        slotName = try c.decode(String.self, forKey: .slotName)
        attachedDevice = try c.decodeIfPresent(String.self, forKey: .attachedDevice) ?? ""
        attachedFleetVehicleToken = try c.decodeIfPresent(String.self, forKey: .attachedFleetVehicleToken)
        policies = try c.decodeIfPresent(MissionRunAssignmentPolicies.self, forKey: .policies) ?? MissionRunAssignmentPolicies()
        slotLifecycleLanes = try c.decodeIfPresent(MissionRunAssignmentSlotStateLanes.self, forKey: .slotLifecycleLanes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(taskId, forKey: .taskId)
        try c.encode(rosterDeviceId, forKey: .rosterDeviceId)
        try c.encode(slotName, forKey: .slotName)
        try c.encode(attachedDevice, forKey: .attachedDevice)
        try c.encodeIfPresent(attachedFleetVehicleToken, forKey: .attachedFleetVehicleToken)
        let hasAbort = policies.abortPreferenceChain != nil && !(policies.abortPreferenceChain?.isEmpty ?? true)
        let hasComplete = policies.completePreferenceChain != nil && !(policies.completePreferenceChain?.isEmpty ?? true)
        let hasReserveSwap = policies.reserveSwapPreferenceChain != nil && !(policies.reserveSwapPreferenceChain?.isEmpty ?? true)
        let hasGeofenceAug = !policies.geofenceAugmentation.isEmpty
        if hasAbort || hasComplete || hasReserveSwap || hasGeofenceAug {
            try c.encode(policies, forKey: .policies)
        }
        try c.encodeIfPresent(slotLifecycleLanes, forKey: .slotLifecycleLanes)
    }

    /// Lanes for runtime / UI: persisted ``slotLifecycleLanes`` when set, otherwise **idle** / **idle** (no slot writers yet).
    var effectiveSlotLifecycleLanes: MissionRunAssignmentSlotStateLanes {
        slotLifecycleLanes ?? MissionRunAssignmentSlotStateLanes()
    }

    /// Roster slot is ready to start when tied to a fleet vehicle or legacy free-text device.
    var hasFleetOrLegacyAssignment: Bool {
        if let t = attachedFleetVehicleToken, !t.isEmpty { return true }
        return !attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension MissionRunAssignment {
    /// Synthetic assignment for fleet resolution / Mission Preflight on a floating reserve **pool** slot (`rosterDeviceId` is a stable filler).
    static func syntheticForReservePool(slot: MissionRunReservePoolSlot) -> MissionRunAssignment {
        MissionRunAssignment(
            id: slot.id,
            rosterDeviceId: slot.id,
            slotName: slot.label,
            attachedDevice: slot.attachedDevice,
            attachedFleetVehicleToken: slot.attachedFleetVehicleToken
        )
    }
}

// MARK: - Start run preflight (arm probe UI + store)

enum MissionRunPreflightSlotPhase: String, Equatable {
    case pending
    case testing
    case passed
    case failed
}

/// Which binding start-run Mission Preflight is probing (roster vs floating reserve pool).
enum MissionRunPreflightSlotIdentity: Equatable, Hashable, Sendable {
    case rosterAssignment(UUID)
    case floatingReservePool(taskID: UUID, slotID: UUID)
}

/// One roster row in the Mission Preflight overlay (before / during / after arm probe).
struct MissionRunPreflightUITarget: Equatable {
    let identity: MissionRunPreflightSlotIdentity
    let displayTitle: String
    let assignment: MissionRunAssignment
}

/// Task-grouped roster targets for Mission Preflight (horizontal card rows per task).
struct MissionRunPreflightUIProbeSection: Identifiable, Equatable {
    let id: UUID
    let title: String
    let titleMuted: Bool
    let targets: [MissionRunPreflightUITarget]
}

struct MissionRunPreflightSlotRow: Identifiable, Equatable {
    let identity: MissionRunPreflightSlotIdentity
    let slotName: String
    var phase: MissionRunPreflightSlotPhase
    var detail: String
    /// Set when **`phase == .failed`** — operator hints from `PreflightFailureAdvisor` (pattern-matched; extend in `PreflightFailureAdvisor.swift`).
    var remediationAdvice: PreflightFailureRemediationAdvice? = nil

    var id: UUID {
        switch identity {
        case .rosterAssignment(let id): return id
        case .floatingReservePool(_, let slotID): return slotID
        }
    }
}

/// Result of a **single-vehicle** preflight probe (Vehicles preflight modal).
struct SingleVehiclePreflightProbeResult: Equatable {
    let passed: Bool
    /// True when an arm command was sent and succeeded (vehicle likely armed); false if already armed or probe failed before arm.
    let armedDuringProbe: Bool
    let detail: String
    let remediationAdvice: PreflightFailureRemediationAdvice?
}

/// Optional hub snapshot gates applied inside ``MissionControlStore/runSingleVehiclePreflightProbe`` **before**
/// the arm-probe recipe. Modes that add checks must keep them **telemetry-only** (no catalogue dispatch) unless
/// they use a distinct ``preflightAuditSource`` from start-run / swap-in arm probes.
enum MissionControlPreflightTelemetryGateMode: Equatable {
    /// Arm recipe only (after readiness / live-mission policy).
    case none
    /// MC-R floating reserve **swap-in**: GPS/battery/health/staleness/mode substring gates (see ``MissionControlReserveSwapInPreflightGates``).
    case reserveSwapIn
}

enum MissionRunEventLevel: String, Equatable {
    case info
    case warning
    case error
}

/// Speaker for mission runtime events (log prefix / export). Use ``missionControl`` for MC automation;
/// ``assistant(key:)`` for any AI / automation assistant (Paladin and future ones); ``operator`` for
/// human-operator-attributed edits and commands (`displayName` is the operator callsign from
/// `GeneralSettingsStore`, when set). Assistant `key` is resolved to a display name through
/// ``MissionRunAssistantRegistry`` so adding a new assistant requires no renderer changes.
enum MissionRunEventSpeaker: Equatable {
    case missionControl
    case assistant(key: String)
    case vehicleSlot(String)
    case `operator`(displayName: String?)
}

/// Addressee for a mission runtime event ("@target"). Renders structurally between the speaker and the
/// body in MCR rows and plain-text export — `[Wrapper][Speaker] @target body` — and gets its own color
/// pulled from the canonical resolver (task map color, slot vehicle color, etc.). When unset, an
/// `effectiveTarget` is derived from the speaker (see ``MissionRunEvent/effectiveTarget``); the
/// default rule is "vehicles report to MissionControl". Assistant `key` resolves through
/// ``MissionRunAssistantRegistry`` for display. Slot targets are id-keyed (assignment id) so renames
/// stay live and same-name slots / deletions are unambiguous; the human callsign is resolved from the
/// current ``MissionRunAssignment`` set at render time.
enum MissionRunEventTarget: Equatable {
    case missionControl
    case assistant(key: String)
    case task(id: UUID, name: String)
    case slot(id: UUID)
    case `operator`(displayName: String?)
}

// MARK: - Assistant registry

/// Lightweight identity for an AI / automation assistant that participates in MC-R logging
/// (e.g. Paladin). Held by ``MissionRunAssistantRegistry`` and resolved at render time so new
/// assistants only need to register their `key -> displayName` to appear properly in `[Speaker]`
/// prefixes and `@target` mentions.
struct MissionRunAssistantProfile: Equatable {
    let key: String
    let displayName: String

    init(key: String, displayName: String) {
        self.key = key
        self.displayName = displayName
    }
}

/// Process-wide registry mapping ``MissionRunCommandIssuerKey``-style assistant keys to their
/// human display names (used for `[Paladin]` / `@paladin` style log rendering). Assistants register
/// themselves on init (e.g. ``PaladinMissionAssistant``) so renderers stay free of hardcoded
/// assistant names — no renderer change is needed when a new assistant is added.
@MainActor
final class MissionRunAssistantRegistry {
    static let shared = MissionRunAssistantRegistry()

    private var profilesByKey: [String: MissionRunAssistantProfile] = [:]

    private init() {}

    func register(_ profile: MissionRunAssistantProfile) {
        profilesByKey[profile.key] = profile
    }

    func unregister(forKey key: String) {
        profilesByKey.removeValue(forKey: key)
    }

    func profile(forKey key: String) -> MissionRunAssistantProfile? {
        profilesByKey[key]
    }

    /// Display name for a registered assistant; falls back to the raw key so unknown assistants
    /// still render legibly in logs.
    func displayName(forKey key: String) -> String {
        profilesByKey[key]?.displayName ?? key
    }
}

struct MissionRunEvent: Identifiable, Equatable {
    let id: UUID
    let at: Date
    let level: MissionRunEventLevel
    /// Mission task id (map tint); optional when mission-wide.
    let taskID: UUID?
    /// Task name for `[Name]` tag and plain-text export.
    let taskLabel: String?
    let speaker: MissionRunEventSpeaker
    /// Explicit addressee; when `nil`, ``effectiveTarget`` derives one from `speaker` + `taskID/Label`.
    let target: MissionRunEventTarget?
    /// Materialized default (export) line; normally from ``StructuredLogTemplateCatalog`` via `templateKey` + `templateParams` at append time.
    let message: String
    /// Stable id for catalog / localization (`{{param}}` in patterns). New emissions should always set this.
    let templateKey: String?
    let templateParams: [String: String]

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        level: MissionRunEventLevel = .info,
        taskID: UUID? = nil,
        taskLabel: String? = nil,
        speaker: MissionRunEventSpeaker = .missionControl,
        target: MissionRunEventTarget? = nil,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        self.id = id
        self.at = at
        self.level = level
        self.taskID = taskID
        self.taskLabel = taskLabel
        self.speaker = speaker
        self.target = target
        self.message = message
        self.templateKey = templateKey
        self.templateParams = templateParams
    }

    /// Resolved addressee for rendering. Explicit ``target`` wins. Otherwise we fall back to the
    /// "directed messaging" default for that speaker:
    /// - `vehicleSlot` (and `assistant` when no other context) → ``missionControl``
    /// - `missionControl` → the task it was logging about (when `taskID`/`taskLabel` are set), else the operator
    /// - `operator` → ``missionControl`` (operator with no explicit target is addressing the runtime as a whole)
    var effectiveTarget: MissionRunEventTarget {
        if let target { return target }
        switch speaker {
        case .vehicleSlot:
            return .missionControl
        case .assistant:
            if let tid = taskID, let label = taskLabel, !label.isEmpty {
                return .task(id: tid, name: label)
            }
            return .missionControl
        case .missionControl:
            if let tid = taskID, let label = taskLabel, !label.isEmpty {
                return .task(id: tid, name: label)
            }
            return .operator(displayName: nil)
        case .operator:
            return .missionControl
        }
    }
}

/// Resolves the human task name for MC-R log lines from roster + mission template (role-track context may be absent).
func missionRunLogResolvedTaskName(assignment: MissionRunAssignment, mission: Mission) -> String? {
    if let tid = assignment.taskId,
       let n = mission.routeMacro.tasks.first(where: { $0.id == tid })?.name,
       !n.isEmpty {
        return n
    }
    let enabled = mission.routeMacro.tasks.filter(\.enabled)
    if enabled.count == 1, let n = enabled.first?.name, !n.isEmpty {
        return n
    }
    return nil
}

extension MissionRunEvent {
    /// Canonical `[Task]` prefix for MC-R logs: stored labels, `taskID`, roster slot, ``templateParams/slot``, or ``templateParams/slotID`` (assignment uuid).
    func resolvedTaskLogPrefix(mission: Mission?, assignments: [MissionRunAssignment]) -> String? {
        if let t = taskLabel, !t.isEmpty { return t }
        guard let mission else { return nil }

        let assignmentForPrefix: MissionRunAssignment? = {
            if case .vehicleSlot(let s) = speaker,
               let a = assignments.first(where: { $0.slotName == s }) {
                return a
            }
            if let raw = templateParams["slotID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               let uuid = UUID(uuidString: raw),
               let a = assignments.first(where: { $0.id == uuid }) {
                return a
            }
            if let raw = templateParams["slot"] {
                let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty, let a = assignments.first(where: { $0.slotName == s }) {
                    return a
                }
            }
            return nil
        }()

        if let a = assignmentForPrefix,
           let squad = MissionControlSquadUtilities.liveLogPrimarySquadTaskChipIfApplicable(
               assignmentID: a.id,
               mission: mission,
               assignments: assignments
           ) {
            return squad.chipLabel
        }
        if let a = assignmentForPrefix,
           let n = missionRunLogResolvedTaskName(assignment: a, mission: mission), !n.isEmpty {
            return n
        }
        if let tid = taskID,
           let n = mission.routeMacro.tasks.first(where: { $0.id == tid })?.name, !n.isEmpty {
            return n
        }
        return nil
    }
}

/// Who is accountable for a command (operator profile, MC automation, or an assistant such as Paladin).
enum MissionRunCommandIssuer: String, Codable, Equatable, CaseIterable {
    case `operator`
    case missionControl
    case assistant
}

/// Common `issuerKey` values (`operator` should eventually be a stable operator id from account/session).
enum MissionRunCommandIssuerKey {
    static let paladin = "paladin"
    /// Until operator identity is wired through HQ, local UI acts as this logical operator.
    static let localOperator = "localOperator"
    static let plannerAbort = "planner.abort"
    /// Issuer key for post–swap-in catalogue steps on the displaced stream (distinct audit trail from whole-run abort).
    static let plannerReserveSwapPostCommit = "planner.reserveSwapPostCommit"
    static let runTeardown = "run.teardown"
    /// Orderly **complete-policy** recovery wind-down (map-point move+park, RTL, etc.) issued by MRE after cycle / task end.
    /// Distinct from ``localOperator`` so recipe ``confirmInLiveMission`` steps can auto-ack without per-vehicle prompt spam.
    static let completePolicyWindDown = "missioncontrol.complete_policy.wind_down"
    static let staging = "staging"
    static let missionExecute = "mission.execute"
    /// Between-cycles **fallback** fleet dispatch after the operator-selected primary between-cycles command fails (see ``MissionRunFleetDispatch/betweenCyclesFailureFallbackDispatch``).
    static let betweenCyclesFallback = "mission.between_cycles.fallback"
    /// Mission Run SIM cleanup — sequential ``recipe.fleet.vehicle.do.park`` after ``markCompleted`` (audit / operator prompt correlation).
    static let runCleanupPark = "missioncontrol.run_cleanup.park"
    /// Catalogue ``fleetVehicleDoMissionClear`` during run-complete SIM cleanup (audit).
    static let runCleanupMissionClear = "missioncontrol.run_cleanup.mission_clear"
    /// Catalogue ``fleetVehicleDoGeofenceClear`` during run-complete SIM cleanup (audit).
    static let runCleanupGeofenceClear = "missioncontrol.run_cleanup.geofence_clear"
    /// MC-R **Fences** triage: push resolved template geofences to every bound roster vehicle (Layer 1 recipes).
    static let mcrLiveGeofenceFleetPush = "missioncontrol.mcr.live_geofence_fleet_push"
}

/// How a mission-run slot reaches Layer 0: ``FleetVehicleCommand`` queue, a
/// catalogue ``FleetCommandsCatalogue/invoke`` (atom or composite), or a Layer 1
/// ``FleetRecipeRunner/run`` recipe (MRE mission start uses the upload→arm→start recipe).
enum MissionRunFleetDispatch: Equatable {
    case vehicleCommand(FleetVehicleCommand)
    case catalogue(name: FleetCommandName, parameters: FleetCommandParameters)
    case recipe(name: FleetRecipeName, parameters: FleetRecipeParameters)
}

extension MissionRunFleetDispatch {
    /// Preferential **abort** tactics (non–map-point). **Return to Launch** in production uses
    /// ``MissionRunEnvironment/returnToLaunchFleetDispatch(assignmentID:planningHub:)`` (MCS launch at Start Run);
    /// this static helper’s RTL case is the stack ``returnToLaunch()`` fallback only.
    @MainActor
    static func preferentialAbortTacticDispatch(_ kind: MissionRunAbortTactic.Kind) -> MissionRunFleetDispatch? {
        switch kind {
        case .returnToLaunch:
            return MissionControlOperatorLaunchPosePolicy.stackReturnToLaunchFallback
        case .loiter:
            return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        case .park:
            return .catalogue(name: .fleetVehicleDoPark, parameters: .empty)
        case .nearestOpenMapPoint:
            return nil
        }
    }

    /// Preferential **complete** tactics (non–map-point, non–``MissionRunCompleteTactic/Kind/none``).
    @MainActor
    static func preferentialCompleteTacticDispatch(_ kind: MissionRunCompleteTactic.Kind) -> MissionRunFleetDispatch? {
        switch kind {
        case .returnToLaunch:
            return MissionControlOperatorLaunchPosePolicy.stackReturnToLaunchFallback
        case .loiter:
            return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        case .park:
            return .catalogue(name: .fleetVehicleDoPark, parameters: .empty)
        case .nearestOpenMapPoint, .none:
            return nil
        }
    }

    /// Preferential **reserve swap** tactics (non–map-point, non–``MissionRunReserveSwapTactic/Kind/none``).
    @MainActor
    static func preferentialReserveSwapTacticDispatch(_ kind: MissionRunReserveSwapTactic.Kind) -> MissionRunFleetDispatch? {
        switch kind {
        case .returnToLaunch:
            return MissionControlOperatorLaunchPosePolicy.stackReturnToLaunchFallback
        case .loiter:
            return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        case .park:
            return .catalogue(name: .fleetVehicleDoPark, parameters: .empty)
        case .nearestOpenMapPoint, .none:
            return nil
        }
    }

    /// Between-cycle shaping for continuous tasks: same catalogue / recipe stack as preferential policies.
    @MainActor
    static func betweenCyclesTaskDispatch(_ action: MissionTaskBetweenCyclesAction) -> MissionRunFleetDispatch? {
        switch action {
        case .returnToLaunch:
            return MissionControlOperatorLaunchPosePolicy.stackReturnToLaunchFallback
        case .holdPosition:
            return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        case .park:
            return .catalogue(name: .fleetVehicleDoPark, parameters: .empty)
        }
    }

    /// When the configured between-cycles primary dispatch fails, issue **Loiter** for roster slots that expect **UAV**,
    /// otherwise **Park** (UGV / USV / UUV / unknown).
    @MainActor
    static func betweenCyclesFailureFallbackDispatch(expectedGranularClass: FleetVehicleType) -> MissionRunFleetDispatch {
        switch expectedGranularClass.universalClass {
        case .uav:
            return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        case .ugv, .usv, .uuv, .unknown:
            return .catalogue(name: .fleetVehicleDoPark, parameters: .empty)
        }
    }

    /// Short operator-facing label for between-cycles policy dispatches (Return to Launch / Loiter / Park).
    @MainActor
    var betweenCyclesPolicyLogLabel: String {
        switch self {
        case .recipe(let name, let params):
            if name == FleetMissionRecipeRegistrations.doReturnHomeRecipeName {
                return "Return to Launch"
            }
            if name == FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
               params.string(named: "procedureLogSummary")
                   == MissionControlOperatorLaunchPosePolicy.returnToLaunchProcedureLogSummary {
                return "Return to Launch"
            }
            return name.rawValue
        case .catalogue(let name, _):
            switch name {
            case .fleetVehicleDoLoiter: return "Loiter"
            case .fleetVehicleDoPark: return "Park"
            default: return name.rawValue
            }
        case .vehicleCommand(let command):
            return command.missionRunDispatchShortLabel
        }
    }
}

/// Operator-selected stabilisation before a **Live Drive handoff** (MC-R Engage — see ``README.md`` Live Drive control session).
/// Uses the same fleet catalogue atoms as preferential abort/complete **park** / **loiter** paths.
enum MissionRunEngageStabilizeDispatchKind: String, CaseIterable, Sendable, Equatable {
    case park
    case loiter

    var missionRunFleetDispatch: MissionRunFleetDispatch {
        switch self {
        case .park: return .catalogue(name: .fleetVehicleDoPark, parameters: .empty)
        case .loiter: return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        }
    }

    var operatorShortLabel: String {
        switch self {
        case .park: return "Park"
        case .loiter: return "Loiter"
        }
    }
}

/// Operator **continue mission** after PX4 UGV offboard park (Layer 1 recipe — see ``FleetMissionRecipeRegistrations/doContinueMissionAfterOperatorParkRecipeName``).
enum MissionRunOperatorContinueMissionAfterParkDispatchKind: String, Sendable, Equatable {
    case armModeMissionStart

    var missionRunFleetDispatch: MissionRunFleetDispatch {
        .recipe(
            name: FleetMissionRecipeRegistrations.doContinueMissionAfterOperatorParkRecipeName,
            parameters: .empty
        )
    }

    var operatorShortLabel: String { "Continue mission" }
}

struct MissionRunIssuedCommand: Identifiable, Equatable {
    let id: UUID
    let assignmentID: UUID
    let slotName: String
    let vehicleTokenKey: String
    let dispatch: MissionRunFleetDispatch
    let issuer: MissionRunCommandIssuer
    /// Stable id for the issuer (e.g. operator uuid, or ``MissionRunCommandIssuerKey/paladin`` for Paladin).
    let issuerKey: String
    let category: FleetVehicleCommandCategory

    /// Attribution string for FleetLink / logs (`issuer:issuerKey`).
    var fleetDispatchSourceLabel: String { "\(issuer.rawValue):\(issuerKey)" }

    init(
        id: UUID = UUID(),
        assignmentID: UUID,
        slotName: String,
        vehicleTokenKey: String,
        dispatch: MissionRunFleetDispatch,
        issuer: MissionRunCommandIssuer,
        issuerKey: String,
        category: FleetVehicleCommandCategory = .missionControl
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.slotName = slotName
        self.vehicleTokenKey = vehicleTokenKey
        self.dispatch = dispatch
        self.issuer = issuer
        self.issuerKey = issuerKey
        self.category = category
    }

    /// Convenience for call sites that still issue a raw MAVSDK-shaped command.
    init(
        id: UUID = UUID(),
        assignmentID: UUID,
        slotName: String,
        vehicleTokenKey: String,
        command: FleetVehicleCommand,
        issuer: MissionRunCommandIssuer,
        issuerKey: String,
        category: FleetVehicleCommandCategory = .missionControl
    ) {
        self.init(
            id: id,
            assignmentID: assignmentID,
            slotName: slotName,
            vehicleTokenKey: vehicleTokenKey,
            dispatch: .vehicleCommand(command),
            issuer: issuer,
            issuerKey: issuerKey,
            category: category
        )
    }

    func reattributed(issuer: MissionRunCommandIssuer, issuerKey: String) -> MissionRunIssuedCommand {
        MissionRunIssuedCommand(
            id: id,
            assignmentID: assignmentID,
            slotName: slotName,
            vehicleTokenKey: vehicleTokenKey,
            dispatch: dispatch,
            issuer: issuer,
            issuerKey: issuerKey,
            category: category
        )
    }
}

struct MissionRunAbortPlanEntry: Equatable, Identifiable {
    let assignmentID: UUID
    let slotName: String
    /// Resolved ordered tactics for this slot (after assignment → task → mission merge).
    let resolvedPreferenceChain: [MissionRunAbortTactic]
    /// First tactic the core planner successfully bound to a dispatch (optimistic walk).
    let chosenTactic: MissionRunAbortTactic?
    /// Ordered fleet dispatches for this slot’s abort wind-down.
    ///
    /// The planner always prefixes ``FleetCommandName/fleetVehicleDoMissionClear`` when a fleet token
    /// is present so the autopilot mission is torn down before RTL / move+park / loiter / park tactics run.
    let issuedCommands: [MissionRunIssuedCommand]

    var id: UUID { assignmentID }
}

struct MissionRunAbortPlan: Equatable {
    let builtAt: Date
    let trigger: MissionRunAbortTrigger
    let entries: [MissionRunAbortPlanEntry]
}

// MARK: - Executor command queue (tagged batches)

/// Queue bucket; **when** is ``MissionRunQueuedCommandDispatch`` on each batch.
enum MissionRunCommandQueueTag: String, CaseIterable, Hashable {
    case abort = "missionControl.queue.abort"
    /// Recovery wind-down after the current mission cycle (``MissionRunCompleteTactic`` preference chain), distinct from abort policy.
    case complete = "missionControl.queue.complete"
    case missionStart = "missionControl.queue.missionStart"
    /// Post–reserve-swap-in handoff (mission clear on displaced stream, later upload / start / wind-down).
    case reserveSwapPostCommit = "missionControl.queue.reserveSwapPostCommit"
}

/// When a ``MissionRunQueuedCommandBatch`` should be delivered to the fleet.
enum MissionRunQueuedCommandDispatch: Equatable {
    case immediate
    case at(Date)
    /// After the autopilot mission cycle completes (same gating as graceful operator stop).
    case afterMissionCycle
}

/// One enqueue unit: a tag (for revocation/replacement), a dispatch rule, and fleet commands.
struct MissionRunQueuedCommandBatch: Identifiable, Equatable {
    let id: UUID
    let tag: MissionRunCommandQueueTag
    let dispatch: MissionRunQueuedCommandDispatch
    let commands: [MissionRunIssuedCommand]
    /// When ``tag`` is ``MissionRunCommandQueueTag/reserveSwapPostCommit``, set so sequential dispatch can log
    /// pipeline phases after fleet acks and post operator toasts on failure.
    let reserveSwapPostCommitAckContext: MissionRunReserveSwapPostCommitBatchAckContext?

    init(
        id: UUID = UUID(),
        tag: MissionRunCommandQueueTag,
        dispatch: MissionRunQueuedCommandDispatch,
        commands: [MissionRunIssuedCommand],
        reserveSwapPostCommitAckContext: MissionRunReserveSwapPostCommitBatchAckContext? = nil
    ) {
        self.id = id
        self.tag = tag
        self.dispatch = dispatch
        self.commands = commands
        self.reserveSwapPostCommitAckContext = reserveSwapPostCommitAckContext
    }
}

extension MissionRunQueuedCommandBatch {
    /// Short dispatch label for mission logs (run-complete suppression, etc.).
    var dispatchLogLabel: String {
        switch dispatch {
        case .immediate:
            return "immediate"
        case .at:
            return "at"
        case .afterMissionCycle:
            return "after_mission_cycle"
        }
    }
}

struct MissionRunPassResult: Equatable {
    var events: [MissionRunEvent]
    var commands: [MissionRunIssuedCommand]
}

enum MissionControlTaskTopology: String, Equatable {
    case singleTask = "singlePath"
    case multiTask = "multiPath"
}

enum MissionControlTeamTopology: String, Equatable {
    case singleVehiclePerTask = "singleVehiclePerPath"
    case multiVehicleTeam
}

enum MissionControlWorkPartitionMode: String, Equatable {
    case taskOwned = "pathOwned"
    case segmentOwned
    case waypointOwned
}

enum MissionControlHandoffMode: String, Equatable {
    case none
    case thresholdDriven
    case scheduled
}

struct MissionControlVehicleBinding: Equatable {
    let tokenKey: String
    let title: String
    let vehicleIDText: String
    let status: VehicleLifecycleStatus
}

struct MissionControlRoleTrack: Identifiable, Equatable {
    let id: UUID
    let taskID: UUID?
    let taskDisplayName: String?
    let assignmentID: UUID
    let rosterDeviceID: UUID
    let slotName: String
    let boundVehicle: MissionControlVehicleBinding?
}

struct MissionControlPlan: Equatable {
    let missionID: UUID
    let runID: UUID
    let missionName: String
    let createdAt: Date
    let taskTopology: MissionControlTaskTopology
    let teamTopology: MissionControlTeamTopology
    let workPartitionMode: MissionControlWorkPartitionMode
    let handoffMode: MissionControlHandoffMode
    let roleTracks: [MissionControlRoleTrack]
    /// Geofences **merged for planning** per enabled task id: template + run mission-wide augmentation + run per-task augmentation (see ``MissionRunGeofencePolicyResolution/planningGeofences``).
    let planningGeofencesByTaskID: [UUID: [MissionGeofence]]
}

enum MissionControlPlanMutation: Equatable {
    case upsertTaskStartDelay(taskID: UUID, startDelayValue: Double, startDelayUnit: DelayUnit)
    case removeTaskStartDelay(taskID: UUID)
    case replaceAssignmentVehicleToken(assignmentID: UUID, vehicleTokenKey: String?)
    case updateAssignmentTask(assignmentID: UUID, taskID: UUID?)
}

struct MissionControlPlanChangeSet: Equatable {
    let previousPlan: MissionControlPlan?
    let currentPlan: MissionControlPlan
    let addedAssignmentIDs: [UUID]
    let removedAssignmentIDs: [UUID]
    let changedAssignmentIDs: [UUID]
    let changedTaskIDs: [UUID]
}

struct MissionControlPlanChangeResult: Equatable {
    let revision: Int
    let plan: MissionControlPlan
    let changeSet: MissionControlPlanChangeSet
    let source: String
    let reason: String?
}

struct MissionControlPlanRevisionRecord: Equatable, Identifiable {
    let id: UUID
    let revision: Int
    let at: Date
    let source: String
    let reason: String?
    let summary: String

    init(
        id: UUID = UUID(),
        revision: Int,
        at: Date = Date(),
        source: String,
        reason: String?,
        summary: String
    ) {
        self.id = id
        self.revision = revision
        self.at = at
        self.source = source
        self.reason = reason
        self.summary = summary
    }
}

enum MissionControlTaskTagName {
    static func taskContext(for assignment: MissionRunAssignment, mission: Mission?) -> (id: UUID, label: String)? {
        guard let mission else { return nil }
        if let pid = assignment.taskId,
           let path = mission.routeMacro.tasks.first(where: { $0.id == pid }) {
            let t = path.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        if let path = mission.routeMacro.tasks.first(where: { $0.enabled }) {
            let t = path.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        if let path = mission.routeMacro.tasks.first {
            let t = path.name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        return nil
    }
}

enum MissionControlPlanCompiler {
    @MainActor
    static func compile(
        run: MissionRunEnvironment,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) -> MissionControlPlan {
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
        let taskTopology: MissionControlTaskTopology = enabledTasks.count <= 1 ? .singleTask : .multiTask

        var boundByToken: [String: MissionPickableFleetVehicle] = [:]
        for vehicle in fleetVehicles {
            boundByToken[vehicle.token.storageKey] = vehicle
        }

        let roleTracks: [MissionControlRoleTrack] = run.assignments.map { assignment in
            let boundVehicle = assignment.attachedFleetVehicleToken.flatMap { token in
                boundByToken[token].map { vehicle in
                    MissionControlVehicleBinding(
                        tokenKey: token,
                        title: vehicle.title,
                        vehicleIDText: vehicle.vehicleIDText,
                        status: vehicle.lifecycleStatus
                    )
                }
            }
            let ctx = MissionControlTaskTagName.taskContext(for: assignment, mission: mission)
            return MissionControlRoleTrack(
                id: UUID(),
                taskID: ctx?.id ?? assignment.taskId,
                taskDisplayName: ctx?.label,
                assignmentID: assignment.id,
                rosterDeviceID: assignment.rosterDeviceId,
                slotName: assignment.slotName,
                boundVehicle: boundVehicle
            )
        }

        let roleCountByTask = Dictionary(grouping: roleTracks, by: \.taskID).mapValues(\.count)
        let primarySquadCountByTask = MissionControlSquadUtilities.boundPrimaryCountByTaskID(
            mission: mission,
            assignments: run.assignments
        )
        let hasMultiVehicleTask = roleCountByTask.values.contains { $0 > 1 }
        let hasMultiPrimarySquadTask = primarySquadCountByTask.values.contains { $0 > 1 }
        let usesTeamPartition = hasMultiVehicleTask || hasMultiPrimarySquadTask
        let teamTopology: MissionControlTeamTopology = usesTeamPartition ? .multiVehicleTeam : .singleVehiclePerTask
        let workPartitionMode: MissionControlWorkPartitionMode = usesTeamPartition ? .segmentOwned : .taskOwned
        let handoffMode: MissionControlHandoffMode = .none

        let planningGeofencesByTaskID = Dictionary(uniqueKeysWithValues: enabledTasks.map { task in
            (
                task.id,
                MissionRunGeofencePolicyResolution.planningGeofences(
                    taskID: task.id,
                    mission: mission,
                    missionWideRunAugmentation: run.policies.missionGeofenceAugmentation,
                    perTaskRunAugmentation: run.taskGeofenceAugmentationsByTaskID[task.id] ?? []
                )
            )
        })

        return MissionControlPlan(
            missionID: mission.id,
            runID: run.id,
            missionName: run.missionName,
            createdAt: Date(),
            taskTopology: taskTopology,
            teamTopology: teamTopology,
            workPartitionMode: workPartitionMode,
            handoffMode: handoffMode,
            roleTracks: roleTracks,
            planningGeofencesByTaskID: planningGeofencesByTaskID
        )
    }
}

// MARK: - Reserve swap (operator copy)

/// Operator-facing strings for Mission Control Running reserve swap-in confirms, toasts, and phase-log detail.
enum MissionRunReserveSwapOperatorCopy {
    /// Body for reserve pool pick confirm (short; detail belongs in docs / failure flows).
    static let reserveSwapPoolPickConfirmMessage: String =
        "An arm check runs on this reserve before it takes the roster slot. If it fails, try again after fixing the aircraft, or pick another pool row."

    /// Prepended to the reserve arm-check failure dialog so operators know roster state is unchanged.
    static let reserveSwapPreflightFailurePrologue: String =
        "Nothing on the roster changes until the arm check passes successfully."

    // MARK: MC-R toasts (floating pool swap-in + autonomous fixed)

    static let toastReserveSwapChecksRunning = "Reserve swap checks are still running — wait for them to finish."
    static let toastBerthBusyWaitArmPreflightBeforeSwap = "This berth is busy — wait for arm preflight on it to finish before swapping in."
    static let toastMissionTemplateUnavailable = "Mission template unavailable."
    static let toastRosterSlotNotBoundToTask = "This roster slot is not bound to a task."
    static let toastSlotNotOnTaskRoster = "This slot is not on the task’s roster."
    static let toastNoFloatingReserveForSlotFallback = "No floating reserve available for this slot."
    static let toastReserveSwapStillRunningWaitHub = "A reserve swap is still running — wait for hub checks to finish."
    static let toastReserveSwapInProgressWaitHub = "Reserve swap is in progress — wait for hub checks to finish."
    static let toastReserveSwapAlreadyRunning = "Reserve swap is already running — wait for it to finish."
    static let toastPoolBerthNoLongerOnTask = "That pool berth is no longer on this task."
    static let toastNoLiveReserveLink = "No live link for this reserve — connect the vehicle or SIM, then try again."
    static let toastBerthArmPreflightRunningBeforeSwap = "This berth’s arm preflight is still running — wait for it to finish before swapping in."
    static let toastFloatingReserveSwappedOntoRoster = "Reserve swapped onto roster slot."
    static let toastFloatingReserveAutoSwappedOntoRoster = "Reserve auto-swapped onto roster (autonomous engagement)."
    static let toastNoEligibleFloatingReserveForTask = "No eligible floating reserve for this task."
    static let toastRosterSlotNotFoundOnRun = "Roster slot not found on this run."
    static let toastRosterSlotNotOnSelectedTask = "This roster slot is not on the selected task."
    static let toastEveryPoolAircraftMatchesRosterBinding = "Every pool vehicle on this task already matches this roster fleet binding."
    static let toastNoPoolClassMatchForRosterSlot = "No floating reserve on this task matches this roster slot’s vehicle class."
    static let toastReserveSwapReturnRejectedPrefix = "Reserve swap aborted — the roster vehicle cannot occupy the pool berth:"
    static let toastReserveSwapPoolClearFailed = "Reserve swap could not clear the pool berth. Check the mission log for this run."
    /// Post-commit handoff: displaced stream mission clear failed at the fleet layer (roster already committed).
    static let toastReserveSwapPostCommitDisplacedMissionClearFailed =
        "Reserve swap handoff: mission clear on the former active failed. Later handoff steps were skipped — check the mission log."
    /// Post-commit handoff: vacancy upload / arm / start recipe failed.
    static let toastReserveSwapPostCommitVacancyMissionHandoffFailed =
        "Reserve swap handoff: mission upload on the new active failed. Wind-down on the former active was skipped — check the mission log."
    /// Post-commit handoff: displaced wind-down catalogue or recipe failed.
    static let toastReserveSwapPostCommitDisplacedWindDownFailed =
        "Reserve swap handoff: wind-down on the former active failed — check the mission log."
    static let toastReserveSwapPickRejectedStale = "Reserve swap aborted: that vehicle is no longer eligible (duplicate binding, written off for floating reserve on this run, or operational state changed). Refresh the roster and pool."
    static let toastPoolBerthNotAvailableForRosterSlot = "That pool berth is not available for this roster slot."
    static let toastReserveSwapBlockedSessionPhase =
        "Reserve swaps are unavailable while this run is in recovery, completed, aborting, or aborted."
    static let toastNoLiveReserveAutoSwapSkipped = "No live link for this reserve — auto-swap skipped."
    static let toastReserveAutoSwapSkippedPreflight = "Reserve auto-swap skipped — reserve vehicle did not pass preflight."
    static let toastFixedReserveNotAvailableForRosterSlot = "That fixed reserve row is not available for this roster slot."
    static let toastEveryReserveMatchesRosterBinding = "Every reserve on this task already matches this roster fleet binding."
    static let toastReserveAutoSwapAbortedPickRejected = "Reserve auto-swap aborted: that vehicle is no longer eligible (duplicate binding, written off for floating reserve on this run, or operational state changed)."

    static func toastReserveSwapReturnRejected(_ outcome: MissionRunReservePoolReturnAssignmentOutcome) -> String {
        "\(toastReserveSwapReturnRejectedPrefix) \(reservePoolReturnRejectionSummary(outcome))"
    }

    /// Short `detail` for ``MissionRunReserveSwapPhaseLogTemplateKey`` when a floating pool **roster commit** path fails.
    static func floatingPoolSwapRosterCommitFailureDetail(_ outcome: MissionRunFloatingReserveSwapOutcome) -> String {
        switch outcome {
        case .success: return "unexpected success branch"
        case .noEligiblePoolSlots: return "No eligible pool berths on this task."
        case .assignmentNotFound: return "Roster assignment id not found."
        case .assignmentNotBoundToTask: return "Roster assignment not bound to this task."
        case .identicalFleetBindingNoOp: return "Identical fleet binding — no-op."
        case .noClassCompatiblePoolSlots: return "No class-compatible pool slot."
        case .returnRejected(let r): return "Return-to-pool rejected: \(reservePoolReturnRejectionSummary(r))."
        case .poolClearFailed: return "Pool clear failed after commit attempt."
        case .pickRejectedDuplicateOrStaleBinding: return "Pre-commit dedupe or operational gate rejected pick."
        case .poolSlotNotEligible: return "Pool berth not in enumerated candidates for this vacancy."
        case .blockedBySessionPhase: return "Reserve swap blocked — run session is not accepting roster reserve swaps."
        }
    }

    /// Short `detail` for phase logs when a fixed roster reserve swap commit fails.
    static func fixedRosterSwapRosterCommitFailureDetail(_ outcome: MissionRunFixedRosterReserveSwapOutcome) -> String {
        switch outcome {
        case .success: return "unexpected success branch"
        case .assignmentNotFound: return "Assignment not found."
        case .assignmentNotBoundToTask: return "Assignment not bound to task."
        case .reserveNotEligibleForVacancy: return "Fixed reserve row not eligible for this vacancy."
        case .identicalFleetBindingNoOp: return "Identical fleet binding — no-op."
        case .pickRejectedDuplicateOrStaleBinding: return "Pre-commit dedupe or operational gate rejected pick."
        case .blockedBySessionPhase: return "Reserve swap blocked — run session is not accepting roster reserve swaps."
        }
    }

    private static func reservePoolReturnRejectionSummary(_ r: MissionRunReservePoolReturnAssignmentOutcome) -> String {
        switch r {
        case .rejectedNoBinding: return "no binding"
        case .rejectedFleetVehicleWrittenOff: return "vehicle written off for this run’s floating reserve pool"
        case .rejectedFleetContextUnavailable: return "fleet link unavailable"
        case .rejectedFleetVehicleUnresolved: return "vehicle not resolved"
        case .rejectedVehicleNotOperational: return "vehicle not operational"
        case .rejectedBatteryCritical: return "battery critical"
        case .appended, .mergedExisting: return "unexpected"
        }
    }
}

// MARK: - Reserve swap (VoiceOver / map bridge)

/// Concise strings for **MC-R** reserve swap context: Leaflet marker `title` (via ``MapVehicleMarker/accessibilityTitle``) and SwiftUI health-card summaries.
enum MissionRunReserveSwapAccessibilityCopy {
    /// Leaflet `title` / ``MapVehicleMarker/accessibilityTitle`` for floating pool hub markers.
    static func floatingPoolMapMarker(
        taskName: String,
        berthLabel: String,
        swapPickActiveOnTask: Bool,
        markerIsEligiblePickTarget: Bool,
        browsingThisBerthOnTask: Bool
    ) -> String {
        var parts: [String] = [
            "Floating reserve map marker",
            "task \(taskName)",
            "berth \(berthLabel)",
        ]
        if browsingThisBerthOnTask {
            parts.append("floating reserve berth overlay is open for this marker")
        }
        if swapPickActiveOnTask {
            if markerIsEligiblePickTarget {
                parts.append("eligible reserve swap-in pick for this task")
            } else {
                parts.append("reserve swap-in is open on this task")
            }
        }
        return parts.joined(separator: ", ")
    }

    static func rosterVacancyDuringReserveSwapPick(taskName: String, slotName: String) -> String {
        "Roster vacancy \(slotName) on \(taskName). Reserve swap-in is open; pick a class-compatible floating reserve on the map or in the candidate strip."
    }

    static func rosterBenchReserveDuringReserveSwapPick(taskName: String, slotName: String) -> String {
        "Bench reserve \(slotName) on \(taskName). Fixed reserve roster row while reserve swap-in is open on this task."
    }

    static func floatingPoolStripSwapPickCandidate(taskName: String, berthLabel: String, aircraftShortID: String) -> String {
        "Reserve swap candidate \(berthLabel) on \(taskName), aircraft \(aircraftShortID). Opens a confirmation; arm checks run before the roster changes."
    }

    static func floatingPoolStripBrowseCandidate(taskName: String, berthLabel: String, aircraftShortID: String) -> String {
        "Floating reserve berth \(berthLabel) on \(taskName), aircraft \(aircraftShortID). Opens the floating reserve berth overlay."
    }

    static func floatingPoolBrowseEmptyStrip() -> String {
        "No floating reserve berths on this task. Add floating reserve berths in Mission Control setup."
    }

    static func reserveSwapPickEmptyStrip(title: String, subtitle: String) -> String {
        "\(title). \(subtitle)"
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

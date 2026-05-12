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
    /// Between-cycle behavior (delay / between-cycles commands) before the next cycle.
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

/// In-flight **intent** for a task’s abort or complete/recovery protocol — distinct from settled ``MissionTaskState``
/// (see ``MissionRunEnvironment/taskAttemptingByTaskID``, recomputed in ``MissionRunEnvironment/refreshDerivedTaskStates()``).
///
/// v1 derives this only from per-task orchestration flags (issued wind-down + graceful **pending**). When per-slot
/// evidence exists (``TaskRosterAssignmentStatesToDo.md`` §3+), clearing rules may split from ``MissionTaskState``.
enum MissionTaskAttemptState: String, Codable, CaseIterable, Equatable, Hashable {
    /// Abort-policy wind-down **commands were dispatched** for this task; operator / future slot rollup not finished.
    case abortWindDownIssued
    /// Complete-policy recovery wind-down **was dispatched**; recovery acknowledgement not finished.
    case recoveryWindDownIssued
    /// **Abort after this autopilot cycle** is scheduled; dispatch has not run yet.
    case abortWindDownScheduledAfterCycle
    /// **Complete after this cycle** is scheduled; dispatch has not run yet.
    case recoveryWindDownScheduledAfterCycle

    /// Short operator-facing title (MC-R / banners).
    var displayTitle: String {
        switch self {
        case .abortWindDownIssued:
            return "Abort wind-down in progress"
        case .recoveryWindDownIssued:
            return "Recovery wind-down in progress"
        case .abortWindDownScheduledAfterCycle:
            return "Abort scheduled after this cycle"
        case .recoveryWindDownScheduledAfterCycle:
            return "Complete scheduled after this cycle"
        }
    }
}

/// Per-roster-slot mission orchestration progress within a run (``TaskRosterAssignmentStatesToDo.md`` §2).
///
/// Values persist on ``MissionRunAssignment/slotLifecycleLanes`` (README **Roster slot state storage** — option **(a)** on-row). Operator-facing roster chip copy is ``displayTitle`` (**v1 UX lock**); revisit when §3 evidence surfaces ship.
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
        case .policySucceeded: return "Policy complete"
        case .policyFailed: return "Policy failed"
        case .blockedNoVehicle: return "No vehicle bound"
        case .notApplicableEmptySlot: return "Empty slot"
        case .supersededReassigned: return "Reassigned"
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
    static func worstAmong(assignments: [MissionRunAssignment]) -> (severity: GuardianFeedbackSeverity, title: String)? {
        var bestRank = -1
        var picked: (GuardianFeedbackSeverity, String)?
        for a in assignments {
            let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: a.effectiveSlotLifecycleLanes)
            guard let sev = merged.missionControlRosterBadgeSeverity else { continue }
            let r = rank(sev)
            if r > bestRank {
                bestRank = r
                picked = (sev, merged.displayTitle)
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

/// Queued “finish after this autopilot mission cycle” intent: **abort** uses abort-policy commands; **complete** uses recovery RTL wind-down.
enum MissionRunGracefulStopKind: String, Codable, Equatable {
    case none
    case abortAfterCycle
    case completeAfterCycle
}

/// Fleet-command scope for Mission Control orchestration (task today; squad / single slot later).
enum MissionRunCommandTarget: Equatable, Hashable, Sendable {
    case task(UUID)
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

/// Run-level policy bundle for ``MissionRunEnvironment`` (engagement only; abort/complete live on ``Mission`` / ``MissionTask`` / ``MissionRunAssignmentPolicies``).
struct MissionRunPolicies: Equatable {
    var engagement: MissionRunEngagementRules

    init(engagement: MissionRunEngagementRules = .default) {
        self.engagement = engagement
    }
}

/// Per-assignment policy overrides. Non-`nil` values override the owning task’s policy, which overrides the mission default.
struct MissionRunAssignmentPolicies: Codable, Equatable {
    /// When non-empty, replaces the resolved **abort preference chain** for this slot (see ``MissionRunPolicyResolution``).
    var abortPreferenceChain: [MissionRunAbortTactic]?
    /// When non-empty, replaces the resolved **complete (recovery) preference chain** for this slot.
    var completePreferenceChain: [MissionRunCompleteTactic]?

    init(abortPreferenceChain: [MissionRunAbortTactic]? = nil, completePreferenceChain: [MissionRunCompleteTactic]? = nil) {
        self.abortPreferenceChain = abortPreferenceChain
        self.completePreferenceChain = completePreferenceChain
    }
}

/// Resolves abort / complete autopilot actions for a roster slot: **assignment → task → mission** (most specific wins).
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
        if hasAbort || hasComplete {
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
    /// Canonical `[Task]` prefix for MC-R logs: stored labels, `taskID`, roster slot, or `slot` in ``templateParams``.
    func resolvedTaskLogPrefix(mission: Mission?, assignments: [MissionRunAssignment]) -> String? {
        if let t = taskLabel, !t.isEmpty { return t }
        if let tid = taskID, let mission,
           let n = mission.routeMacro.tasks.first(where: { $0.id == tid })?.name, !n.isEmpty {
            return n
        }
        guard let mission else { return nil }
        let slotKey: String? = {
            switch speaker {
            case .vehicleSlot(let s):
                return s
            case .assistant, .missionControl, .operator:
                guard let raw = templateParams["slot"] else { return nil }
                let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }
        }()
        if let slot = slotKey,
           let a = assignments.first(where: { $0.slotName == slot }) {
            return missionRunLogResolvedTaskName(assignment: a, mission: mission)
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
    static let runTeardown = "run.teardown"
    static let staging = "staging"
    static let missionExecute = "mission.execute"
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
    /// Preferential **abort** tactics (non–map-point): RTL uses the Layer‑1 return-home recipe; loiter / park use catalogue atoms.
    @MainActor
    static func preferentialAbortTacticDispatch(_ kind: MissionRunAbortTactic.Kind) -> MissionRunFleetDispatch? {
        switch kind {
        case .returnToLaunch:
            return .recipe(
                name: FleetMissionRecipeRegistrations.doReturnHomeRecipeName,
                parameters: .empty
            )
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
            return .recipe(
                name: FleetMissionRecipeRegistrations.doReturnHomeRecipeName,
                parameters: .empty
            )
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
            return .recipe(
                name: FleetMissionRecipeRegistrations.doReturnHomeRecipeName,
                parameters: .empty
            )
        case .holdPosition:
            return .catalogue(name: .fleetVehicleDoLoiter, parameters: .empty)
        case .land:
            return .catalogue(name: .fleetVehicleDoLand, parameters: .empty)
        case .none:
            return nil
        }
    }
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

    init(id: UUID = UUID(), tag: MissionRunCommandQueueTag, dispatch: MissionRunQueuedCommandDispatch, commands: [MissionRunIssuedCommand]) {
        self.id = id
        self.tag = tag
        self.dispatch = dispatch
        self.commands = commands
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
        let hasMultiVehicleTask = roleCountByTask.values.contains { $0 > 1 }
        let teamTopology: MissionControlTeamTopology = hasMultiVehicleTask ? .multiVehicleTeam : .singleVehiclePerTask
        let workPartitionMode: MissionControlWorkPartitionMode = hasMultiVehicleTask ? .segmentOwned : .taskOwned
        let handoffMode: MissionControlHandoffMode = .none

        return MissionControlPlan(
            missionID: mission.id,
            runID: run.id,
            missionName: run.missionName,
            createdAt: Date(),
            taskTopology: taskTopology,
            teamTopology: teamTopology,
            workPartitionMode: workPartitionMode,
            handoffMode: handoffMode,
            roleTracks: roleTracks
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
    static let toastEveryPoolAircraftMatchesRosterBinding = "Every pool aircraft on this task already matches this roster fleet binding."
    static let toastNoPoolClassMatchForRosterSlot = "No floating reserve on this task matches this roster slot’s vehicle class."
    static let toastReserveSwapReturnRejectedPrefix = "Reserve swap aborted — the roster aircraft cannot occupy the pool berth:"
    static let toastReserveSwapPoolClearFailed = "Reserve swap could not clear the pool berth. Check the mission log for this run."
    static let toastReserveSwapPickRejectedStale = "Reserve swap aborted: that aircraft is no longer eligible (duplicate binding, written off, or operational state changed). Refresh the roster and pool."
    static let toastPoolBerthNotAvailableForRosterSlot = "That pool berth is not available for this roster slot."
    static let toastNoLiveReserveAutoSwapSkipped = "No live link for this reserve — auto-swap skipped."
    static let toastReserveAutoSwapSkippedPreflight = "Reserve auto-swap skipped — reserve aircraft did not pass preflight."
    static let toastFixedReserveNotAvailableForRosterSlot = "That fixed reserve row is not available for this roster slot."
    static let toastEveryReserveMatchesRosterBinding = "Every reserve on this task already matches this roster fleet binding."
    static let toastReserveAutoSwapAbortedPickRejected = "Reserve auto-swap aborted: that aircraft is no longer eligible (duplicate binding, written off, or operational state changed)."

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
        }
    }

    private static func reservePoolReturnRejectionSummary(_ r: MissionRunReservePoolReturnAssignmentOutcome) -> String {
        switch r {
        case .rejectedNoBinding: return "no binding"
        case .rejectedFleetVehicleWrittenOff: return "aircraft written off for this run’s pool"
        case .rejectedFleetContextUnavailable: return "fleet link unavailable"
        case .rejectedFleetVehicleUnresolved: return "vehicle not resolved"
        case .rejectedVehicleNotOperational: return "aircraft not operational"
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

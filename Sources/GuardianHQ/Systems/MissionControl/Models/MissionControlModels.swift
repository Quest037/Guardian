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
enum MissionRunAbortPolicy: String, Codable, Equatable, CaseIterable, Identifiable {
    case returnToLaunch
    case holdPosition
    case land
    /// Do not issue an autopilot command from policy alone (run teardown may still occur elsewhere).
    case none

    var id: String { rawValue }

    /// MC Setup **Rules** tab menu labels.
    var setupMenuLabel: String {
        switch self {
        case .returnToLaunch: return "Return to Launch"
        case .holdPosition: return "Hold Position"
        case .land: return "Land"
        case .none: return "None"
        }
    }

    /// MC Setup **Rules** abort dropdown ordering (**Return to Launch** first; includes all planner-backed values).
    static var setupPickerCases: [MissionRunAbortPolicy] {
        [.returnToLaunch, .holdPosition, .land, .none]
    }
}

/// Autopilot-facing action when a run completes for recovery (resolved **assignment → task → mission** via ``MissionRunPolicyResolution``).
enum MissionRunCompletePolicy: String, Codable, Equatable, CaseIterable, Identifiable {
    case returnToLaunch
    case holdPosition
    case land
    case none

    var id: String { rawValue }

    var setupMenuLabel: String {
        switch self {
        case .returnToLaunch: return "Return to Launch"
        case .holdPosition: return "Hold Position"
        case .land: return "Land"
        case .none: return "None"
        }
    }

    static var setupPickerCases: [MissionRunCompletePolicy] {
        [.returnToLaunch, .holdPosition, .land, .none]
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
    var abort: MissionRunAbortPolicy?
    var complete: MissionRunCompletePolicy?

    init(abort: MissionRunAbortPolicy? = nil, complete: MissionRunCompletePolicy? = nil) {
        self.abort = abort
        self.complete = complete
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

    static func resolvedAbortPolicy(assignment: MissionRunAssignment, mission: Mission?) -> MissionRunAbortPolicy {
        if let slot = assignment.policies.abort { return slot }
        if let mission,
           let tid = resolvedTaskId(for: assignment, mission: mission),
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }),
           let override = task.abortPolicyOverride {
            return override
        }
        return mission?.routeMacro.rules.missionAbortPolicy ?? .returnToLaunch
    }

    static func resolvedCompletePolicy(assignment: MissionRunAssignment, mission: Mission?) -> MissionRunCompletePolicy {
        if let slot = assignment.policies.complete { return slot }
        if let mission,
           let tid = resolvedTaskId(for: assignment, mission: mission),
           let task = mission.routeMacro.tasks.first(where: { $0.id == tid }),
           let override = task.completePolicyOverride {
            return override
        }
        return mission?.routeMacro.rules.missionCompletePolicy ?? .returnToLaunch
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
    /// Optional setup-stage override for where a bound SIM should start before mission execution.
    var simStartOverrideCoord: RouteCoordinate?
    var policies: MissionRunAssignmentPolicies

    init(
        id: UUID = UUID(),
        taskId: UUID? = nil,
        rosterDeviceId: UUID,
        slotName: String,
        attachedDevice: String = "",
        attachedFleetVehicleToken: String? = nil,
        simStartOverrideCoord: RouteCoordinate? = nil,
        policies: MissionRunAssignmentPolicies = MissionRunAssignmentPolicies()
    ) {
        self.id = id
        self.taskId = taskId
        self.rosterDeviceId = rosterDeviceId
        self.slotName = slotName
        self.attachedDevice = attachedDevice
        self.attachedFleetVehicleToken = attachedFleetVehicleToken
        self.simStartOverrideCoord = simStartOverrideCoord
        self.policies = policies
    }

    enum CodingKeys: String, CodingKey {
        case id, taskId, legacyAssignmentTaskUUID = "pathId", rosterDeviceId, slotName, attachedDevice, attachedFleetVehicleToken, simStartOverrideCoord
        case policies
        case abortPolicy
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
        simStartOverrideCoord = try c.decodeIfPresent(RouteCoordinate.self, forKey: .simStartOverrideCoord)
        if let decodedPolicies = try c.decodeIfPresent(MissionRunAssignmentPolicies.self, forKey: .policies) {
            policies = decodedPolicies
        } else if let legacyAbort = try c.decodeIfPresent(MissionRunAbortPolicy.self, forKey: .abortPolicy) {
            policies = MissionRunAssignmentPolicies(abort: legacyAbort)
        } else {
            policies = MissionRunAssignmentPolicies()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(taskId, forKey: .taskId)
        try c.encode(rosterDeviceId, forKey: .rosterDeviceId)
        try c.encode(slotName, forKey: .slotName)
        try c.encode(attachedDevice, forKey: .attachedDevice)
        try c.encodeIfPresent(attachedFleetVehicleToken, forKey: .attachedFleetVehicleToken)
        try c.encodeIfPresent(simStartOverrideCoord, forKey: .simStartOverrideCoord)
        if policies.abort != nil || policies.complete != nil {
            try c.encode(policies, forKey: .policies)
        }
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

struct MissionRunIssuedCommand: Identifiable, Equatable {
    let id: UUID
    let assignmentID: UUID
    let slotName: String
    let vehicleTokenKey: String
    let command: FleetVehicleCommand
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
        command: FleetVehicleCommand,
        issuer: MissionRunCommandIssuer,
        issuerKey: String,
        category: FleetVehicleCommandCategory = .missionControl
    ) {
        self.id = id
        self.assignmentID = assignmentID
        self.slotName = slotName
        self.vehicleTokenKey = vehicleTokenKey
        self.command = command
        self.issuer = issuer
        self.issuerKey = issuerKey
        self.category = category
    }

    func reattributed(issuer: MissionRunCommandIssuer, issuerKey: String) -> MissionRunIssuedCommand {
        MissionRunIssuedCommand(
            id: id,
            assignmentID: assignmentID,
            slotName: slotName,
            vehicleTokenKey: vehicleTokenKey,
            command: command,
            issuer: issuer,
            issuerKey: issuerKey,
            category: category
        )
    }
}

struct MissionRunAbortPlanEntry: Equatable, Identifiable {
    let assignmentID: UUID
    let slotName: String
    let resolvedPolicy: MissionRunAbortPolicy
    /// Present when a fleet token exists, policy maps to a command, and the token validates.
    let issuedCommand: MissionRunIssuedCommand?

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
    /// Recovery wind-down after the current mission cycle (``MissionRunCompletePolicy``), distinct from abort policy.
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
    case updateAssignmentSimStartOverride(assignmentID: UUID, coordinate: RouteCoordinate?)
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

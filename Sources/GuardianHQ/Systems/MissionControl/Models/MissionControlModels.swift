import Foundation

enum MissionRunSessionPhase: String, Equatable {
    case draft
    case compiled
    /// Plan is ready; waiting for a scheduled execution instant (e.g. one-off future start) before staging/mission passes run.
    case staging
    case executing
    case recovery
    case completed
    case failed
}

/// Per-task lifecycle label for Mission Control runtime (derived on ``MissionRunEnvironment``).
enum MissionTaskState: String, Codable, CaseIterable, Equatable, Hashable {
    /// Mission Control is sending missions to task-force aircraft (upload / staging pass to drones).
    case compiling
    /// MC considers all roster aircraft for the task to have missions loaded; awaiting start / cycle.
    case ready
    /// Task force is getting ready to execute (e.g. countdown, arming, manual prep).
    case staging
    case executing
    /// Between-cycle behavior (delay / between-cycles commands) before the next cycle.
    case between
    /// Orderly wind-down after successful task completion; roster follows recovery protocol.
    case recovery
    /// Abort protocol in progress on the task force (MC-directed; aircraft confirm separately).
    case aborting
    /// Abort protocol finished for this task (operator or future fleet confirmation).
    case aborted
    /// Task force has finished recovery / wind-up for this task.
    case completed

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
        case .aborted: return "Aborted"
        case .completed: return "Completed"
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
    case oneOffAutopilotFinished
}

// MARK: - Abort (scheduling → planner → fleet commands)

/// Autopilot-facing action when a run aborts (resolved per assignment via ``MissionRunPolicies`` / ``MissionRunAssignmentPolicies``).
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

/// Run-level policy bundle for ``MissionRunEnvironment``.
struct MissionRunPolicies: Equatable {
    var abort: MissionRunAbortPolicy
    var engagement: MissionRunEngagementRules

    init(abort: MissionRunAbortPolicy = .returnToLaunch, engagement: MissionRunEngagementRules = .default) {
        self.abort = abort
        self.engagement = engagement
    }
}

/// Per-assignment policy overrides. ``abort`` of `nil` inherits the run’s ``MissionRunPolicies/abort``.
struct MissionRunAssignmentPolicies: Codable, Equatable {
    var abort: MissionRunAbortPolicy?

    init(abort: MissionRunAbortPolicy? = nil) {
        self.abort = abort
    }
}

/// What triggered building an abort plan (for logging / future execution).
enum MissionRunAbortTrigger: String, Equatable {
    case now
    case afterCycle
}

/// Per-run override (minutes) after Paladin begins execution before this task’s MAVLink mission upload/start. When absent, the mission template’s ``MissionTask/startDelay`` applies. MC Setup **Timing** tab **Tasks** card.
struct TaskStartDelay: Codable, Equatable, Identifiable {
    var id: UUID { taskId }
    var taskId: UUID
    /// Clamped 0…59; **0** is equivalent to omitting this task from the list.
    var startDelayMinutes: Int

    enum CodingKeys: String, CodingKey {
        case taskId
        case legacyJSONTaskUUID = "pathId"
        case startDelayMinutes
    }

    init(taskId: UUID, startDelayMinutes: Int) {
        self.taskId = taskId
        self.startDelayMinutes = startDelayMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try c.decodeIfPresent(UUID.self, forKey: .taskId)
            ?? c.decodeIfPresent(UUID.self, forKey: .legacyJSONTaskUUID)
            ?? UUID()
        startDelayMinutes = try c.decodeIfPresent(Int.self, forKey: .startDelayMinutes) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(taskId, forKey: .taskId)
        try c.encode(startDelayMinutes, forKey: .startDelayMinutes)
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
        if policies.abort != nil {
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

/// Speaker for mission runtime events. Mission Control is the default mission runner.
enum MissionRunEventSpeaker: Equatable {
    case missionControl
    case paladin
    case vehicleSlot(String)
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
    /// Default English (or raw vehicle text); used when no template override is registered for `templateKey`.
    let message: String
    /// Stable id for future localization / string tables (`{{param}}` in patterns).
    let templateKey: String?
    let templateParams: [String: String]

    init(
        id: UUID = UUID(),
        at: Date = Date(),
        level: MissionRunEventLevel = .info,
        taskID: UUID? = nil,
        taskLabel: String? = nil,
        speaker: MissionRunEventSpeaker = .missionControl,
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
        self.message = message
        self.templateKey = templateKey
        self.templateParams = templateParams
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
            case .paladin, .missionControl:
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
        category: FleetVehicleCommandCategory = .paladin
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
    case upsertTaskStartDelay(taskID: UUID, startDelayMinutes: Int)
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

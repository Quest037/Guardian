import Foundation

enum MissionRunSessionPhase: String, Equatable {
    case draft
    case compiled
    /// Plan is ready; waiting for a scheduled execution instant (e.g. one-off future start) before staging/mission passes run.
    case staging
    case executing
    case completed
    case failed
}

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

// MARK: - Abort (scheduling → planner → fleet commands)

/// Autopilot-facing action when a run aborts (resolved per assignment via ``MissionRunPolicies`` / ``MissionRunAssignmentPolicies``).
enum MissionRunAbortPolicy: String, Codable, Equatable, CaseIterable, Identifiable {
    case returnToLaunch
    case holdPosition
    case land
    /// Do not issue an autopilot command from policy alone (run teardown may still occur elsewhere).
    case none

    var id: String { rawValue }
}

/// Run-level policy bundle for ``MissionRunEnvironment``.
struct MissionRunPolicies: Equatable {
    var abort: MissionRunAbortPolicy

    init(abort: MissionRunAbortPolicy = .returnToLaunch) {
        self.abort = abort
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

/// Loop / continuous schedule is waiting before starting the next autopilot mission cycle.
struct MissionCycleIntermission: Equatable {
    /// When the delayed restart task is due to fire.
    let restartAt: Date
    /// Length of this wait (seconds), for progress fill.
    let totalDelay: TimeInterval
    let scheduleMode: MissionRunScheduleMode
}

/// Per-path loop delay (minutes between full autopilot cycles). **MC Setup** will edit these; when a path is absent, the run uses ``MissionRunEnvironment/loopIntervalMinutes``.
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
    var policies: MissionRunAssignmentPolicies

    init(
        id: UUID = UUID(),
        pathId: UUID? = nil,
        rosterDeviceId: UUID,
        slotName: String,
        attachedDevice: String = "",
        attachedFleetVehicleToken: String? = nil,
        simStartOverrideCoord: RouteCoordinate? = nil,
        policies: MissionRunAssignmentPolicies = MissionRunAssignmentPolicies()
    ) {
        self.id = id
        self.pathId = pathId
        self.rosterDeviceId = rosterDeviceId
        self.slotName = slotName
        self.attachedDevice = attachedDevice
        self.attachedFleetVehicleToken = attachedFleetVehicleToken
        self.simStartOverrideCoord = simStartOverrideCoord
        self.policies = policies
    }

    enum CodingKeys: String, CodingKey {
        case id, pathId, rosterDeviceId, slotName, attachedDevice, attachedFleetVehicleToken, simStartOverrideCoord
        case policies
        case abortPolicy
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
        try c.encodeIfPresent(pathId, forKey: .pathId)
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
    /// Route path id (map tint); optional when mission-wide.
    let pathID: UUID?
    /// Path name for `[Name]` tag and plain-text export.
    let pathLabel: String?
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
        pathID: UUID? = nil,
        pathLabel: String? = nil,
        speaker: MissionRunEventSpeaker = .missionControl,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        self.id = id
        self.at = at
        self.level = level
        self.pathID = pathID
        self.pathLabel = pathLabel
        self.speaker = speaker
        self.message = message
        self.templateKey = templateKey
        self.templateParams = templateParams
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

enum MissionControlPathTopology: String, Equatable {
    case singlePath
    case multiPath
}

enum MissionControlTeamTopology: String, Equatable {
    case singleVehiclePerPath
    case multiVehicleTeam
}

enum MissionControlWorkPartitionMode: String, Equatable {
    case pathOwned
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
    let pathID: UUID?
    let pathDisplayName: String?
    let assignmentID: UUID
    let rosterDeviceID: UUID
    let slotName: String
    let boundVehicle: MissionControlVehicleBinding?
}

struct MissionControlPlan: Equatable {
    let missionID: UUID
    let runID: UUID
    let missionName: String
    let scheduleMode: MissionRunScheduleMode
    let loopIntervalMinutes: Int
    let loopRepeatCount: Int
    let createdAt: Date
    let pathTopology: MissionControlPathTopology
    let teamTopology: MissionControlTeamTopology
    let workPartitionMode: MissionControlWorkPartitionMode
    let handoffMode: MissionControlHandoffMode
    let roleTracks: [MissionControlRoleTrack]
}

enum MissionControlPlanMutation: Equatable {
    case setScheduleMode(MissionRunScheduleMode)
    case setLoopIntervalMinutes(Int)
    case setLoopRepeatCount(Int)
    case upsertPathStartDelay(pathID: UUID, startDelayMinutes: Int)
    case removePathStartDelay(pathID: UUID)
    case replaceAssignmentVehicleToken(assignmentID: UUID, vehicleTokenKey: String?)
    case updateAssignmentPath(assignmentID: UUID, pathID: UUID?)
    case updateAssignmentSimStartOverride(assignmentID: UUID, coordinate: RouteCoordinate?)
}

struct MissionControlPlanChangeSet: Equatable {
    let previousPlan: MissionControlPlan?
    let currentPlan: MissionControlPlan
    let addedAssignmentIDs: [UUID]
    let removedAssignmentIDs: [UUID]
    let changedAssignmentIDs: [UUID]
    let changedPathIDs: [UUID]
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

enum MissionControlPathTagName {
    static func pathContext(for assignment: MissionRunAssignment, mission: Mission?) -> (id: UUID, label: String)? {
        guard let mission else { return nil }
        if let pid = assignment.pathId,
           let path = mission.routeMacro.paths.first(where: { $0.id == pid }) {
            let t = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        if let path = mission.routeMacro.paths.first(where: { $0.enabled }) {
            let t = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return (path.id, t) }
        }
        if let path = mission.routeMacro.paths.first {
            let t = path.name.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
        let pathTopology: MissionControlPathTopology = enabledPaths.count <= 1 ? .singlePath : .multiPath

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
            let ctx = MissionControlPathTagName.pathContext(for: assignment, mission: mission)
            return MissionControlRoleTrack(
                id: UUID(),
                pathID: ctx?.id ?? assignment.pathId,
                pathDisplayName: ctx?.label,
                assignmentID: assignment.id,
                rosterDeviceID: assignment.rosterDeviceId,
                slotName: assignment.slotName,
                boundVehicle: boundVehicle
            )
        }

        let roleCountByPath = Dictionary(grouping: roleTracks, by: \.pathID).mapValues(\.count)
        let hasTeamPath = roleCountByPath.values.contains { $0 > 1 }
        let teamTopology: MissionControlTeamTopology = hasTeamPath ? .multiVehicleTeam : .singleVehiclePerPath
        let workPartitionMode: MissionControlWorkPartitionMode = hasTeamPath ? .segmentOwned : .pathOwned
        let handoffMode: MissionControlHandoffMode = run.paladinTightCycleHandoff ? .thresholdDriven : .none

        return MissionControlPlan(
            missionID: mission.id,
            runID: run.id,
            missionName: run.missionName,
            scheduleMode: run.scheduleMode,
            loopIntervalMinutes: run.loopIntervalMinutes,
            loopRepeatCount: run.loopRepeatCount,
            createdAt: Date(),
            pathTopology: pathTopology,
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

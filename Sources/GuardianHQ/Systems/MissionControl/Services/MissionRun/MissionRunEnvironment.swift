import Combine
import Foundation
import Mavsdk

/// Mission Control runtime owner for one mission run.
///
/// This object is the canonical Mission Control run environment:
/// - receives setup inputs (template + roster/schedule config),
/// - owns runtime scheduling and delayed execution tasks,
/// - brokers command dispatch via FleetLinkService,
/// - tracks mission execution state and events.
@MainActor
final class MissionRunEnvironment: ObservableObject, Identifiable {
    static let oneOffScheduleTimeTolerance: TimeInterval = 2

    let id: UUID
    @Published var missionId: UUID
    @Published var missionName: String
    @Published var status: MissionRunStatus
    @Published var oneOffStartAt: Date?
    @Published var taskStartDelays: [TaskStartDelay]
    @Published var assignments: [MissionRunAssignment]
    @Published var createdAt: Date
    @Published var startedAt: Date?
    @Published var completedAt: Date?
    @Published var gracefulStopKind: MissionRunGracefulStopKind = .none
    @Published var reportCyclesCompleted: Int?
    @Published var completionKind: MissionRunCompletionKind?
    @Published var policies: MissionRunPolicies = MissionRunPolicies()
    /// Run-only **additional** geofences for a specific task id (merged after mission-wide augmentation).
    @Published var taskGeofenceAugmentationsByTaskID: [UUID: [MissionGeofence]] = [:]

    /// Per-run Mission Control chrome and completion side-effects (cloned from app Mission Run defaults at create time).
    @Published var operatorDisplaySettings: MissionRunOperatorDisplaySettings = .default

    /// Latest execution context from start/cycle ingest; required for queued dispatch and observer enqueue APIs.
    private(set) var lastExecutionContext: MissionRunExecutionContext?

    /// Resolved roster **behavior** roles for the current template / last execution mission (``ResolvedRosterRole``).
    /// Refreshed from ``Mission`` in ``captureExecutionContext(_:)``, ``updateTemplate(_:)``, and run init.
    private(set) var rosterRoleResolutionsByDeviceID: [UUID: ResolvedRosterRole] = [:]

    /// Live **mission points** envelope for this run (rally / extraction / …): seeded from the mission template,
    /// then mutated by operator / MRE / plugins without rewriting the saved ``Mission`` document (see README **Mission template points**).
    ///
    /// While ``status`` is ``MissionRunStatus/setup``, ``updateTemplate(_:)`` re-syncs from the run’s forked
    /// ``Mission/missionPoints`` when the template is replaced; catalog ``MissionStore`` edits do not apply until
    /// the run template is refreshed from that source. After the run leaves setup, this array is **not** replaced from the template—only
    /// ``applyRuntimeMissionPointCreate`` / ``applyRuntimeMissionPointUpdate`` / ``applyRuntimeMissionPointSetClosed``.
    @Published private(set) var runtimeMissionPoints: [MissionPoint] = []

    /// Substatus of MC runtime execution while a run is active.
    @Published private(set) var sessionPhase: MissionRunSessionPhase = .draft

    /// Per-path delayed initial mission starts.
    @Published private(set) var taskStartDeferralByTaskID: [UUID: MissionTaskStartDeferral] = [:]

    /// One-off deferred start countdown.
    @Published private(set) var oneOffDeferredExecution: MissionOneOffDeferredExecution?

    @Published private(set) var cyclesCompleted: Int = 0
    @Published private(set) var events: [MissionRunEvent] = []
    @Published private(set) var template: Mission?
    @Published private(set) var compiledPlan: MissionControlPlan?
    @Published private(set) var finishedMissionCycleVehicleIDsByTaskID: [UUID: Set<String>] = [:]
    /// Primary assignment ids with an in-flight MAVLink mission cycle (source of truth; ``activeCycleTaskIDs`` is synced).
    @Published private(set) var activeCycleSquadAssignmentIDs: Set<UUID> = []
    @Published private(set) var finishedMissionCycleVehicleIDsBySquadAssignmentID: [UUID: Set<String>] = [:]
    @Published private(set) var activeCycleTaskIDs: Set<UUID> = []
    /// Completed autopilot cycles per primary squad (``MissionRunAssignment/id``).
    @Published private(set) var squadCyclesCompletedByAssignmentID: [UUID: Int] = [:]
    /// Derived per-primary-squad state for MC-R (refreshed with task rollup).
    @Published private(set) var squadStateByAssignmentID: [UUID: MissionSquadState] = [:]
    /// Completed autopilot cycles per task this run (continuous / continuous-with-delay). Used with ``MissionTask/cycles``.
    private(set) var taskCyclesCompletedByTaskID: [UUID: Int] = [:]

    /// Operator (or future automation) confirms this task’s roster finished the post-mission **recovery** protocol; then UI shows ``MissionTaskState/completed`` for that task while the run may still be active.
    @Published private(set) var taskMissionEndRecoveryCompletedByTaskID: Set<UUID> = []

    /// Operator (or future automation) confirms this task’s roster finished the **abort** protocol while the run is in ``MissionRunSessionPhase/aborting`` or ``MissionRunSessionPhase/aborted``.
    @Published private(set) var taskMissionEndAbortCompletedByTaskID: Set<UUID> = []

    /// Derived per-task state for MC-R UI (refreshed when run scheduling / lifecycle inputs change).
    @Published private(set) var taskStateByTaskID: [UUID: MissionTaskState] = [:]

    /// MC-led mission-end **intent** (abort vs recovery protocol) before and while fleet work runs — see ``noteMissionTaskEndAttempt(_:forTaskID:)``.
    @Published private(set) var taskMissionEndAttemptByTaskID: [UUID: MissionTaskAttemptState] = [:]

    /// Derived per-task **attempting** line for MC-R UI (mirrors ``taskMissionEndAttemptByTaskID`` with triage / disabled filtering).
    @Published private(set) var taskAttemptingByTaskID: [UUID: MissionTaskAttemptState] = [:]

    /// Operator triage terminal state for a task (``.aborted`` / ``.completed``). ``deriveMissionTaskState`` returns this verbatim so refresh cannot override the operator’s choice.
    @Published private(set) var operatorTriageMarkedMissionTaskStateByTaskID: [UUID: MissionTaskState] = [:]

    /// Optional **floating** reserve **slots** per task (MCS-only run envelope; not persisted on ``Mission`` templates).
    /// See **README.md** → **Floating reserve pool (Mission Control run)**.
    @Published private(set) var reservePoolByTaskID: [UUID: MissionRunReservePool] = [:]

    /// Last **bulk** MCS “Set reserve pool home” lat/lon per task (run envelope). Powers **Reapply reserve pool home** without re-arming the map.
    @Published private(set) var reservePoolBulkSimHomeByTaskID: [UUID: RouteCoordinate] = [:]

    /// Per-roster **operator launch** pose (lat/lon/alt/yaw) captured in MCS at **Start Run** — Return to Launch / Go Home navigate here, not ``RouteMacro/home``.
    @Published private(set) var operatorLaunchPoseByAssignmentID: [UUID: FleetSimState] = [:]

    /// MCS staging map drag coordinates consumed on the next ``captureOperatorLaunchPosesAtRunStart`` (then cleared).
    var pendingMCSLaunchCaptureOverridesByAssignmentID: [UUID: RouteCoordinate] = [:]

    /// One-time hub-derived SIM pose per **roster** assignment, captured on the first execution start (v1 SIM home reset). Keys are ``MissionRunAssignment/id``.
    @Published private(set) var rosterSimStartPoseSnapshotByAssignmentID: [UUID: FleetSimState] = [:]

    /// Hub- or bulk-home-derived SIM pose per **floating reserve pool** slot, filled incrementally while the run executes (keys: ``MissionRunReservePoolSlot/id``).
    @Published private(set) var reservePoolSimStartPoseSnapshotBySlotID: [UUID: FleetSimState] = [:]

    /// True while ``scheduleMissionRunSimCleanupIfNeeded`` async work is in flight (run-complete hook or MCS manual run).
    @Published private(set) var isMissionRunSimCleanupPassRunning = false

    /// Fleet vehicles (``FleetMissionVehicleToken/storageKey``) the operator has **written off** for reserve-pool selection for this run — **airframe** state, not slot state.
    @Published private(set) var writtenOffFleetVehicleStorageKeysForReservePool: Set<String> = []

    /// Task-scoped graceful wind-down scheduled for the next shared autopilot cycle boundary (see scheduling APIs).
    @Published private(set) var pendingMissionTaskGracefulWindDownKindByTaskID: [UUID: MissionRunMissionTaskGracefulPendingKind] = [:]

    /// Primary-squad graceful wind-down at **that squad’s** next MAVLink cycle end (``MissionRunAssignment/id``).
    @Published private(set) var pendingMissionSquadGracefulWindDownKindByAssignmentID: [UUID: MissionRunMissionTaskGracefulPendingKind] = [:]

    /// Fleet abort-policy commands were dispatched for this task (immediate or end-of-cycle); cleared when abort protocol is acknowledged.
    @Published private(set) var missionTaskAbortWindDownIssuedTaskIDs: Set<UUID> = []

    /// Complete-policy wind-down was dispatched for this task; cleared when recovery protocol is acknowledged.
    @Published private(set) var missionTaskCompleteWindDownIssuedTaskIDs: Set<UUID> = []

    /// Per-primary-squad complete-policy dispatch issued while **task-wide** complete wind-down is not yet marked
    /// (multi-primary finite-cycle race: each primary gets its own move+park / chain as soon as **that** squad exhausts
    /// its allotted cycles). Drives §4 ``policyCompleting`` lane starts for ``MissionRunCommandIssuerKey/completePolicyWindDown``.
    @Published private(set) var squadCompletePolicyWindDownIssuedAssignmentIDs: Set<UUID> = []

    /// Per-primary-squad abort-policy dispatch issued without task-wide ``missionTaskAbortWindDownIssuedTaskIDs`` (operator / squad-scoped retry).
    @Published private(set) var squadAbortPolicyWindDownIssuedAssignmentIDs: Set<UUID> = []

    /// §3 auto-ack: this primary squad’s recovery protocol finished (row settled) before or without task-wide recovery ack.
    @Published private(set) var squadMissionEndRecoveryCompletedByAssignmentIDs: Set<UUID> = []

    /// §3 auto-ack: this primary squad’s abort protocol finished (row ``policySucceeded``) before or without task-wide abort ack.
    @Published private(set) var squadMissionEndAbortCompletedByAssignmentIDs: Set<UUID> = []

    /// Tasks that must not receive automatic next-cycle MAVLink starts after a task-scoped wind-down.
    @Published private(set) var missionTaskAutopilotAutostartSuppressedTaskIDs: Set<UUID> = []

    /// Primary squads that must not receive automatic next-cycle MAVLink starts (squad-scoped wind-down).
    @Published private(set) var missionSquadAutopilotAutostartSuppressedAssignmentIDs: Set<UUID> = []
    /// Primary held while wingmen assemble/rebuild convoy on heading-based slots (cleared when formation is ready to launch).
    @Published private(set) var missionSquadConvoyAssemblyHoldAssignmentIDs: Set<UUID> = []

    /// Primary squads the operator parked mid-task (``MissionSquadState/paused``); cleared on **Continue mission**.
    @Published private(set) var missionSquadOperatorPausedAssignmentIDs: Set<UUID> = []

    /// Primary squads held after wingman OFFBOARD/GUIDED reconnect exhaustion (primary mission paused; operator prompt).
    @Published private(set) var missionSquadFormationFollowHaltedPrimaryAssignmentIDs: Set<UUID> = []

    /// Bumps when wingman follow phases change so MC-R roster snapshots refresh.
    @Published private(set) var squadFollowStatusRevision: Int = 0

    /// Wingman slots released from squad follow (map / triage chrome; run session RAM only).
    @Published private(set) var missionRunRosterReleasedAssignmentIDs: Set<UUID> = []

    /// First-wave primaries waiting operator / waypoint release (ordered), keyed by mission task id.
    @Published private(set) var deferredFirstWaveSquadAssignmentIDsByTaskID: [UUID: [UUID]] = [:]

    /// Between-cycle delay before the next MAVLink cycle for one primary squad.
    @Published private(set) var squadStartDeferralByAssignmentID: [UUID: MissionTaskStartDeferral] = [:]

    /// Last lead-primary ``missionProgressCurrent`` snapshot per task (``MissionTask/staggerTrigger`` ``waypointReached`` auto-release).
    internal var waypointStaggerGateLastHubProgressByTaskID: [UUID: Int32] = [:]

    /// Roster / pool assignment ids for which MC‑R **Engage Live Drive** is active: manual streaming owns that
    /// airframe, so autonomous reserve distress automation must not target that vacancy and next-cycle MAVLink
    /// autostart must not run for the mapped mission tasks until the handoff clears (see ``unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission:)``).
    @Published private(set) var missionRunAssignmentIDsWithOperatorLiveDriveHandoff: Set<UUID> = []

    /// Last §3 **pull** conformance promotion to ``policySucceeded`` per ``MissionRunAssignment/id`` (debounce).
    internal var slotPolicyPullConformanceLastSuccessByAssignmentID: [UUID: Date] = [:]

    internal weak var fleetLink: FleetLinkService?
    internal weak var sitl: SitlService?
    internal weak var generalSettings: GeneralSettingsStore?
    private var assistantsByKey: [String: AnyObject] = [:]
    let systems: MissionRunSystems

    /// Persists template mutations performed via ``MissionRunEnvironment`` policy / Rules-of-Engagement APIs.
    /// Set by the layer that owns the ``MissionControlStore`` (typically ``MissionRunDetailView``); when `nil`,
    /// mission/task edits are still applied to the in-memory ``template`` but won't notify the store to re‑index the run.
    var missionTemplatePersister: ((Mission) -> Void)?

    init(
        id: UUID = UUID(),
        mission: Mission,
        oneOffStartAt: Date? = nil,
        taskStartDelays: [TaskStartDelay] = [],
        assignments: [MissionRunAssignment] = [],
        createdAt: Date = Date()
    ) {
        self.systems = MissionRunSystems(
            lifecycle: MissionRunLifecycleSubsystem(),
            logging: MissionRunLoggingSubsystem(),
            commands: MissionRunCommandSubsystem(),
            planner: MissionRunPlannerSubsystem(),
            projections: MissionRunProjectionsSubsystem(),
            executor: MissionRunExecutionSubsystem(),
            scheduling: MissionRunSchedulingSubsystem(),
            policyAuthority: MissionRunPolicyAuthoritySubsystem(),
            squadFollow: MissionRunSquadFollowSubsystem()
        )
        self.id = id
        self.missionId = mission.id
        self.missionName = mission.name
        self.status = .setup
        self.oneOffStartAt = oneOffStartAt
        self.taskStartDelays = taskStartDelays
        self.assignments = assignments
        self.createdAt = createdAt
        self.startedAt = nil
        self.completedAt = nil
        self.gracefulStopKind = .none
        self.reportCyclesCompleted = nil
        self.completionKind = nil
        self.template = mission
        self.systems.lifecycle.environment = self
        self.systems.logging.environment = self
        self.systems.commands.environment = self
        self.systems.planner.environment = self
        self.systems.projections.environment = self
        self.systems.executor.environment = self
        self.systems.scheduling.environment = self
        self.systems.policyAuthority.environment = self
        self.systems.squadFollow.environment = self
        self.systems.squadFollow.cycleLaunchExecutor = self.systems.executor
        refreshDerivedTaskStates()
        syncRosterRoleResolutions(from: mission)
        syncRuntimeMissionPointsFromTemplate(mission, reason: .initial)
    }

    convenience init(
        id: UUID = UUID(),
        missionId: UUID,
        missionName: String,
        status: MissionRunStatus = .setup,
        oneOffStartAt: Date? = nil,
        taskStartDelays: [TaskStartDelay] = [],
        assignments: [MissionRunAssignment] = [],
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        gracefulStopKind: MissionRunGracefulStopKind = .none,
        reportCyclesCompleted: Int? = nil,
        completionKind: MissionRunCompletionKind? = nil
    ) {
        let placeholder = Mission(
            id: missionId,
            name: missionName,
            description: "",
            type: .mobile
        )
        self.init(
            id: id,
            mission: placeholder,
            oneOffStartAt: oneOffStartAt,
            taskStartDelays: taskStartDelays,
            assignments: assignments,
            createdAt: createdAt
        )
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.gracefulStopKind = gracefulStopKind
        self.reportCyclesCompleted = reportCyclesCompleted
        self.completionKind = completionKind
        refreshDerivedTaskStates()
    }

    func attachServices(fleetLink: FleetLinkService, sitl: SitlService, generalSettings: GeneralSettingsStore? = nil) {
        let sameFleet = self.fleetLink === fleetLink
        let sameSitl = self.sitl === sitl
        let sameSettings: Bool = {
            switch (self.generalSettings, generalSettings) {
            case (nil, nil): return true
            case let (l?, r?): return l === r
            case (nil, .some), (.some, nil): return false
            }
        }()
        if sameFleet, sameSitl, sameSettings { return }
        self.fleetLink = fleetLink
        self.sitl = sitl
        if let generalSettings {
            self.generalSettings = generalSettings
        }
    }

    /// Latches ``isMissionRunSimCleanupPassRunning`` for ``scheduleMissionRunSimCleanupIfNeeded`` (same-target extensions cannot write ``private(set)`` storage).
    internal func setMissionRunSimCleanupPassRunning(_ running: Bool) {
        isMissionRunSimCleanupPassRunning = running
    }

    /// Whether ``scheduleMissionRunSimCleanupIfNeeded`` would schedule work (requires attached fleet + SITL services).
    internal func canScheduleMissionRunSimCleanupNow() -> Bool {
        guard let fleetLink, let sitl else { return false }
        let targets = MissionRunSimCleanupParkPolicy.orderedCleanupParkTargets(
            assignments: assignments,
            reservePoolByTaskID: reservePoolByTaskID,
            fleetLink: fleetLink,
            sitl: sitl
        )
        let rosterSnapshots = rosterSimStartPoseSnapshotByAssignmentID
        let poolSnapshots = reservePoolSimStartPoseSnapshotBySlotID
        let shouldTeleport = MissionRunSimHomeRestorePolicy.shouldScheduleAfterMarkCompleted(
            completionKind: completionKind,
            settingsEnabled: operatorDisplaySettings.resetSimToStartPoseOnSuccessfulComplete,
            snapshotsNonEmpty: !rosterSnapshots.isEmpty || !poolSnapshots.isEmpty,
            hasFleetAndSitl: true
        )
        let motionIDs = fleetLink.guardianManagedSitlSessionVehicleIDsSorted()
        return !(targets.isEmpty && !shouldTeleport && motionIDs.isEmpty)
    }

    /// Whether deleting this run should run the waved SIM cleanup pass (kill / mission clear / geofence clear / battery / teleport)
    /// before removing it from ``MissionControlStore``.
    func shouldTriggerSimCleanupBeforeRemoval() -> Bool {
        switch status {
        case .running, .paused, .recovery, .completed:
            return true
        case .setup:
            return canScheduleMissionRunSimCleanupNow()
        }
    }

    /// Waits for any in-flight SIM cleanup pass on this run, then runs ``performMissionRunSimCleanupPassIfNeeded(fleetLink:sitl:)``
    /// when ``shouldTriggerSimCleanupBeforeRemoval()`` is true. Caller should ``attachServices`` first.
    func awaitMissionRunSimCleanupBeforeRemovalIfNeeded() async {
        guard shouldTriggerSimCleanupBeforeRemoval() else { return }
        await awaitInFlightMissionRunSimCleanupPassIfNeeded()
        guard let fleetLink, let sitl else { return }
        await performMissionRunSimCleanupPassIfNeeded(fleetLink: fleetLink, sitl: sitl)
    }

    private static let simCleanupPassWaitPollNs: UInt64 = 50_000_000
    private static let simCleanupPassWaitMaxPolls = 600

    /// Blocks until the run-complete SIM cleanup latch clears (or ~30s), then stops squad convoy follow streams.
    ///
    /// Call before **delete run**, **back to setup**, or other run-shell transitions so MAVSDK kill/hold work does not
    /// race ``SitlService/stop`` / unregister.
    func awaitFleetWindDownBeforeRunShellChange(fleetLink: FleetLinkService, sitl _: SitlService) async {
        await awaitInFlightMissionRunSimCleanupPassIfNeeded()
        await systems.squadFollow.stopAllFollowStreams(fleetLink: fleetLink)
        systems.squadFollow.resetAllFollowState()
    }

    private func awaitInFlightMissionRunSimCleanupPassIfNeeded() async {
        var polls = 0
        while isMissionRunSimCleanupPassRunning, polls < Self.simCleanupPassWaitMaxPolls {
            polls += 1
            try? await Task.sleep(nanoseconds: Self.simCleanupPassWaitPollNs)
        }
    }

    func captureExecutionContext(_ context: MissionRunExecutionContext?) {
        lastExecutionContext = context
        if let mission = context?.mission {
            syncRosterRoleResolutions(from: mission)
        }
    }

    /// Recomputes ``rosterRoleResolutionsByDeviceID`` from a mission snapshot (catalog + plugin overlays).
    func syncRosterRoleResolutions(from mission: Mission) {
        rosterRoleResolutionsByDeviceID = MissionRunRosterRoleResolver.resolutions(for: mission)
    }

    /// One MC log line summarizing non-`.none` behavior roles (template key ``MissionRunLogTemplateKey/rosterBehaviorRolesSnapshot``).
    func logRosterBehaviorRolesSnapshotAtExecutionStart() {
        let rows = rosterRoleResolutionsByDeviceID.values.filter { $0.behaviorRoleID != RosterRole.none.rawValue }
        guard !rows.isEmpty else { return }
        let summary = rows
            .map { "\($0.slotLabel):\($0.behaviorRoleID)" }
            .sorted()
            .joined(separator: ", ")
        systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.rosterBehaviorRolesSnapshot,
            templateParams: ["summary": summary]
        )
    }

    /// When ``lastExecutionContext`` is unset, builds one from the run template and attached link services.
    func effectiveExecutionContextForDispatch() -> MissionRunExecutionContext? {
        if let existing = lastExecutionContext {
            return existing
        }
        guard status == .running || status == .paused || status == .recovery else { return nil }
        guard let fleetLink, let sitl, let mission = template else { return nil }
        return MissionRunExecutionContext(
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            missionProvider: { [weak self] in self?.template }
        )
    }

    /// Starts one task’s MAVLink mission upload / cycle (same pipeline as a deferred start). Only while ``status`` is ``MissionRunStatus/running``.
    @discardableResult
    func startMissionTask(taskID: UUID) -> Bool {
        guard status == .running else { return false }
        if taskStateByTaskID[taskID] == .executing {
            let label = template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
            systems.logging.appendLogEvent(
                level: .info,
                taskID: taskID,
                taskLabel: label,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.startMissionTaskSkippedAlreadyExecuting,
                templateParams: label.map { ["task": $0] } ?? [:]
            )
            return false
        }
        guard let ctx = effectiveExecutionContextForDispatch() else {
            systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.startMissionTaskNoDispatchContext
            )
            return false
        }
        captureExecutionContext(ctx)
        return systems.executor.startMissionTask(taskID: taskID, context: ctx)
    }

    /// Launches the next primary that was held back by first-wave stagger (operator gate or waypoint auto-release path).
    @discardableResult
    func releaseNextDeferredFirstWaveSquad(taskID: UUID) -> Bool {
        guard status == .running else { return false }
        guard sessionPhase == .executing else { return false }
        guard let queue = deferredFirstWaveSquadAssignmentIDsByTaskID[taskID], !queue.isEmpty else { return false }
        guard let ctx = effectiveExecutionContextForDispatch() else {
            systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.startMissionTaskNoDispatchContext
            )
            return false
        }
        captureExecutionContext(ctx)
        return systems.executor.releaseNextDeferredFirstWaveSquad(taskID: taskID, context: ctx)
    }

    /// Operator-triggered: one primary per press (see ``MissionControlOperatorTriggerNextSquadPolicy``).
    @discardableResult
    func startOperatorTriggeredNextSquad(taskID: UUID) -> Bool {
        guard status == .running, sessionPhase == .executing else { return false }
        guard let mission = template,
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.regularity == .operatorTriggered
        else { return false }
        guard let action = MissionControlOperatorTriggerNextSquadPolicy.nextLaunchAction(
            run: self,
            task: task,
            mission: mission
        ) else { return false }
        guard let ctx = effectiveExecutionContextForDispatch() else {
            systems.logging.appendLogEvent(
                level: .warning,
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.startMissionTaskNoDispatchContext
            )
            return false
        }
        captureExecutionContext(ctx)
        return systems.executor.performOperatorTriggerNextSquadAction(
            taskID: taskID,
            action: action,
            context: ctx
        )
    }

    /// When ``staggerTrigger`` is ``waypointReached``, auto-launch the next deferred first-wave primary once the lead vehicle’s MAVLink mission progress crosses the authored waypoint gate.
    func syncHubWaypointStaggerDeferredFirstWaveIfNeeded() {
        guard let mission = template, let fleetLink, let sitl else { return }
        guard status == .running, sessionPhase == .executing else { return }
        guard let ctx = effectiveExecutionContextForDispatch() else { return }
        let enabledCount = mission.routeMacro.tasks.filter(\.enabled).count
        for task in mission.routeMacro.tasks where task.enabled && task.staggerTrigger == .waypointReached {
            guard let queue = deferredFirstWaveSquadAssignmentIDsByTaskID[task.id], !queue.isEmpty else { continue }
            let primaries = MissionControlSquadUtilities.orderedPrimarySquads(
                task: task,
                assignments: assignments,
                rosterDevices: mission.rosterDevices,
                enabledTaskCount: enabledCount
            )
            guard let lead = primaries.first else { continue }
            guard let vid = resolvedFleetStreamVehicleID(
                assignment: lead.0,
                fleetLink: fleetLink,
                sitl: sitl
            ),
                let hub = fleetLink.hubTelemetry(forVehicleID: vid),
                let cur = hub.missionProgressCurrent,
                let tot = hub.missionProgressTotal,
                tot > 0
            else { continue }
            let prev = waypointStaggerGateLastHubProgressByTaskID[task.id] ?? -1
            if MissionTaskStaggerPolicy.shouldAutoReleaseNextDeferredFirstWaveSquad(
                previousProgress: prev,
                currentProgress: cur,
                missionProgressTotal: tot,
                staggerWaypointIndex: task.staggerWaypointIndex
            ) {
                captureExecutionContext(ctx)
                _ = systems.executor.releaseNextDeferredFirstWaveSquad(taskID: task.id, context: ctx)
            }
            waypointStaggerGateLastHubProgressByTaskID[task.id] = cur
        }
    }

    // MARK: - Task-scoped mission wind-down (abort / complete)

    /// Assignments whose compiled or explicit ``MissionRunAssignment/taskId`` maps to `taskID`.
    func assignmentsBoundToMissionTask(taskID: UUID) -> [MissionRunAssignment] {
        assignments.filter { assignment in
            if assignment.taskId == taskID { return true }
            guard let plan = compiledPlan else { return false }
            return plan.roleTracks.contains { $0.assignmentID == assignment.id && $0.taskID == taskID }
        }
    }

    /// Clears persisted §3 / §4 **slot lifecycle lanes** on every roster row so a new run pass does not inherit policy-complete chips from the prior execution.
    func clearAssignmentSlotLifecycleLanesOnAllRows() {
        guard !assignments.isEmpty else { return }
        var next = assignments
        for i in next.indices {
            next[i].slotLifecycleLanes = nil
        }
        assignments = next
    }

    /// Clears task-scoped graceful scheduling, dispatch markers, and autostart suppression (whole-run start / reset).
    ///
    /// - Parameter preserveEndModeSettlement: When `true`, keeps task- and squad-scoped wind-down **issued** markers,
    ///   per-squad terminal ack sets, and autostart suppression so §3 auto-ack can finish after ``enterRunEndMode``.
    internal func clearMissionTaskScopedOrchestrationState(preserveEndModeSettlement: Bool = false) {
        if !pendingMissionTaskGracefulWindDownKindByTaskID.isEmpty {
            pendingMissionTaskGracefulWindDownKindByTaskID = [:]
        }
        if !pendingMissionSquadGracefulWindDownKindByAssignmentID.isEmpty {
            pendingMissionSquadGracefulWindDownKindByAssignmentID = [:]
        }
        if !preserveEndModeSettlement {
            if !missionTaskAbortWindDownIssuedTaskIDs.isEmpty { missionTaskAbortWindDownIssuedTaskIDs = [] }
            if !missionTaskCompleteWindDownIssuedTaskIDs.isEmpty { missionTaskCompleteWindDownIssuedTaskIDs = [] }
            if !missionTaskAutopilotAutostartSuppressedTaskIDs.isEmpty { missionTaskAutopilotAutostartSuppressedTaskIDs = [] }
            if !missionSquadAutopilotAutostartSuppressedAssignmentIDs.isEmpty { missionSquadAutopilotAutostartSuppressedAssignmentIDs = [] }
            if !missionSquadConvoyAssemblyHoldAssignmentIDs.isEmpty { missionSquadConvoyAssemblyHoldAssignmentIDs = [] }
            if !squadCompletePolicyWindDownIssuedAssignmentIDs.isEmpty { squadCompletePolicyWindDownIssuedAssignmentIDs = [] }
            if !squadAbortPolicyWindDownIssuedAssignmentIDs.isEmpty { squadAbortPolicyWindDownIssuedAssignmentIDs = [] }
            if !squadMissionEndRecoveryCompletedByAssignmentIDs.isEmpty { squadMissionEndRecoveryCompletedByAssignmentIDs = [] }
            if !squadMissionEndAbortCompletedByAssignmentIDs.isEmpty { squadMissionEndAbortCompletedByAssignmentIDs = [] }
        }
        if !deferredFirstWaveSquadAssignmentIDsByTaskID.isEmpty { deferredFirstWaveSquadAssignmentIDsByTaskID = [:] }
        if !squadStartDeferralByAssignmentID.isEmpty { squadStartDeferralByAssignmentID = [:] }
        if !waypointStaggerGateLastHubProgressByTaskID.isEmpty { waypointStaggerGateLastHubProgressByTaskID = [:] }
        if !missionRunAssignmentIDsWithOperatorLiveDriveHandoff.isEmpty { missionRunAssignmentIDsWithOperatorLiveDriveHandoff = [] }
        if !operatorTriageMarkedMissionTaskStateByTaskID.isEmpty { operatorTriageMarkedMissionTaskStateByTaskID = [:] }
        if !slotPolicyPullConformanceLastSuccessByAssignmentID.isEmpty { slotPolicyPullConformanceLastSuccessByAssignmentID = [:] }
        if !taskMissionEndAttemptByTaskID.isEmpty { taskMissionEndAttemptByTaskID = [:] }
    }

    /// §3 auto mission-end ack and hub pull promotion while the run is still settling end policy (not after Mark complete).
    internal var allowsMissionEndAutoSettlement: Bool {
        status == .running || status == .paused || status == .recovery
    }

    /// Run entered recovery / aborting: stop new cycles; **preserve** wind-down + terminal ack state for in-flight recipes.
    internal func enterRunEndMode(
        kind: MissionRunCompletionKind,
        operatorWindDown: MissionRunOperatorWindDown,
        oneOffAutopilotFinished: Bool = false
    ) {
        clearMissionTaskScopedOrchestrationState(preserveEndModeSettlement: true)
        systems.scheduling.cancelAllScheduledTasks()
        systems.scheduling.clearDeferredOneOffExecution()
        var cycleSnap = cyclesCompleted
        if oneOffAutopilotFinished {
            cycleSnap = max(1, cycleSnap)
        }
        clearFinishedMissionCycleVehicleIDs()
        clearActiveCycleInFlightTracking()
        clearTaskCycleCompletionCounts()
        completedAt = nil
        gracefulStopKind = .none
        reportCyclesCompleted = cycleSnap
        completionKind = kind
        switch operatorWindDown {
        case .recoveryPhase:
            status = .recovery
            setSessionPhase(.recovery)
        case .abortProtocolPhase:
            setSessionPhase(.aborting)
        }
    }

    /// Operator Mark complete: tear down settlement bookkeeping; no further §3 auto-ack.
    internal func finalizeOrchestrationOnMarkComplete() {
        clearMissionTaskScopedOrchestrationState(preserveEndModeSettlement: false)
        clearFinishedMissionCycleVehicleIDs()
        clearActiveCycleTasks()
        clearTaskCycleCompletionCounts()
    }

    internal func setPendingMissionTaskGracefulWindDown(kind: MissionRunMissionTaskGracefulPendingKind, forTaskID taskID: UUID) {
        clearPendingMissionSquadGracefulWindDownForPrimarySquads(ofTaskID: taskID)
        pendingMissionTaskGracefulWindDownKindByTaskID[taskID] = kind
        refreshDerivedTaskStates()
    }

    /// Clears per-primary-squad pending graceful rows for every primary bound to this task (used when task-wide pending replaces them).
    internal func clearPendingMissionSquadGracefulWindDownForPrimarySquads(ofTaskID taskID: UUID) {
        let aids = Set(primarySquads(forTaskID: taskID).map(\.assignment.id))
        guard !aids.isEmpty else { return }
        var changed = false
        for aid in aids where pendingMissionSquadGracefulWindDownKindByAssignmentID[aid] != nil {
            pendingMissionSquadGracefulWindDownKindByAssignmentID.removeValue(forKey: aid)
            changed = true
        }
        if changed { refreshDerivedTaskStates() }
    }

    internal func setPendingMissionSquadGracefulWindDown(kind: MissionRunMissionTaskGracefulPendingKind, forAssignmentID assignmentID: UUID) {
        if let taskID = taskIDForSquadGracefulMutation(assignmentID: assignmentID) {
            pendingMissionTaskGracefulWindDownKindByTaskID.removeValue(forKey: taskID)
        }
        pendingMissionSquadGracefulWindDownKindByAssignmentID[assignmentID] = kind
        refreshDerivedTaskStates()
    }

    private func taskIDForSquadGracefulMutation(assignmentID: UUID) -> UUID? {
        guard let mission = template else { return nil }
        return resolvedTaskID(forSquadAssignmentID: assignmentID, mission: mission)
    }

    internal func clearPendingMissionTaskGracefulWindDown(forTaskID taskID: UUID? = nil) {
        if let taskID {
            pendingMissionTaskGracefulWindDownKindByTaskID.removeValue(forKey: taskID)
            clearPendingMissionSquadGracefulWindDownForPrimarySquads(ofTaskID: taskID)
        } else {
            pendingMissionTaskGracefulWindDownKindByTaskID.removeAll()
            pendingMissionSquadGracefulWindDownKindByAssignmentID.removeAll()
        }
        refreshDerivedTaskStates()
    }

    internal func clearPendingMissionSquadGracefulWindDown(forAssignmentID assignmentID: UUID) {
        guard pendingMissionSquadGracefulWindDownKindByAssignmentID.removeValue(forKey: assignmentID) != nil else { return }
        refreshDerivedTaskStates()
    }

    internal func consumePendingMissionTaskGracefulWindDown(forTaskID taskID: UUID) -> MissionRunMissionTaskGracefulPendingKind? {
        let v = pendingMissionTaskGracefulWindDownKindByTaskID.removeValue(forKey: taskID)
        if v != nil { refreshDerivedTaskStates() }
        return v
    }

    internal func consumePendingMissionSquadGracefulWindDown(forAssignmentID assignmentID: UUID) -> MissionRunMissionTaskGracefulPendingKind? {
        let v = pendingMissionSquadGracefulWindDownKindByAssignmentID.removeValue(forKey: assignmentID)
        if v != nil { refreshDerivedTaskStates() }
        return v
    }

    internal func markMissionTaskAbortWindDownIssued(forTaskID taskID: UUID) {
        missionTaskAbortWindDownIssuedTaskIDs.insert(taskID)
        missionTaskAutopilotAutostartSuppressedTaskIDs.insert(taskID)
        refreshDerivedTaskStates()
    }

    internal func markMissionTaskCompleteWindDownIssued(forTaskID taskID: UUID) {
        missionTaskCompleteWindDownIssuedTaskIDs.insert(taskID)
        missionTaskAutopilotAutostartSuppressedTaskIDs.insert(taskID)
        refreshDerivedTaskStates()
    }

    /// True only for **whole-run** after-cycle operator intent (``gracefulStopKind``).
    ///
    /// Per-task graceful / issued wind-down must **not** use this — they belong in
    /// ``unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission:)`` so sibling tasks keep independent autostart.
    func shouldSuppressMissionWideBetweenCycleAutostart() -> Bool {
        gracefulStopKind != .none
    }

    /// Records MC-led mission-end **intent** before fleet wind-down commands; **abort** wins if both were ever set.
    internal func noteMissionTaskEndAttempt(_ kind: MissionTaskAttemptState, forTaskID taskID: UUID) {
        var m = taskMissionEndAttemptByTaskID
        switch kind {
        case .abortMissionEnd:
            m[taskID] = .abortMissionEnd
        case .recoveryMissionEnd:
            if m[taskID] != .abortMissionEnd {
                m[taskID] = .recoveryMissionEnd
            }
        }
        taskMissionEndAttemptByTaskID = m
        refreshDerivedTaskStates()
    }

    /// Clears stored mission-end attempt without an extra refresh (caller owns ``refreshDerivedTaskStates()``).
    internal func clearMissionTaskEndAttemptStorage(forTaskID taskID: UUID) {
        guard taskMissionEndAttemptByTaskID[taskID] != nil else { return }
        var m = taskMissionEndAttemptByTaskID
        m.removeValue(forKey: taskID)
        taskMissionEndAttemptByTaskID = m
    }

    /// When the operator explicitly starts a task cycle again, allow autostart bookkeeping and prior task-scoped markers to reset for that path.
    internal func prepareMissionTaskForOperatorRestart(taskID: UUID) {
        clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
        missionTaskAutopilotAutostartSuppressedTaskIDs.remove(taskID)
        missionTaskAbortWindDownIssuedTaskIDs.remove(taskID)
        missionTaskCompleteWindDownIssuedTaskIDs.remove(taskID)
        taskMissionEndRecoveryCompletedByTaskID.remove(taskID)
        taskMissionEndAbortCompletedByTaskID.remove(taskID)
        clearMissionTaskEndAttemptStorage(forTaskID: taskID)
        removeSquadCompletePolicyWindDownIssuedForBoundPrimaries(taskID: taskID)
        removeSquadAbortPolicyWindDownIssuedForBoundPrimaries(taskID: taskID)
        clearPerSquadMissionEndTerminalStateForBoundPrimaries(taskID: taskID)
        var triage = operatorTriageMarkedMissionTaskStateByTaskID
        triage.removeValue(forKey: taskID)
        operatorTriageMarkedMissionTaskStateByTaskID = triage
        refreshDerivedTaskStates()
    }

    /// Clears per-primary terminal squad ack sets for one task (operator restart only — not routine refresh).
    private func clearPerSquadMissionEndTerminalStateForBoundPrimaries(taskID: UUID) {
        guard let mission = template else { return }
        let aids = Set(primarySquads(forTaskID: taskID, mission: mission).map(\.assignment.id))
        guard !aids.isEmpty else { return }
        var recoveryDone = squadMissionEndRecoveryCompletedByAssignmentIDs
        let recoveryBefore = recoveryDone
        aids.forEach { recoveryDone.remove($0) }
        if recoveryDone != recoveryBefore { squadMissionEndRecoveryCompletedByAssignmentIDs = recoveryDone }
        var abortDone = squadMissionEndAbortCompletedByAssignmentIDs
        let abortBefore = abortDone
        aids.forEach { abortDone.remove($0) }
        if abortDone != abortBefore { squadMissionEndAbortCompletedByAssignmentIDs = abortDone }
    }

    /// Latches step-2 complete for this primary squad (sticky across task-wide wind-down and rollup refresh).
    internal func markSquadMissionEndRecoveryCompleted(forAssignmentID assignmentID: UUID) {
        guard !squadMissionEndRecoveryCompletedByAssignmentIDs.contains(assignmentID) else { return }
        var next = squadMissionEndRecoveryCompletedByAssignmentIDs
        next.insert(assignmentID)
        squadMissionEndRecoveryCompletedByAssignmentIDs = next
    }

    internal func markSquadMissionEndAbortCompleted(forAssignmentID assignmentID: UUID) {
        guard !squadMissionEndAbortCompletedByAssignmentIDs.contains(assignmentID) else { return }
        var next = squadMissionEndAbortCompletedByAssignmentIDs
        next.insert(assignmentID)
        squadMissionEndAbortCompletedByAssignmentIDs = next
    }

    /// Clears per-squad complete-policy dispatch markers for every primary bound to this task (operator restart / triage).
    internal func removeSquadCompletePolicyWindDownIssuedForBoundPrimaries(taskID: UUID) {
        guard let mission = template else { return }
        let aids = Set(primarySquads(forTaskID: taskID, mission: mission).map(\.assignment.id))
        guard !aids.isEmpty else { return }
        var next = squadCompletePolicyWindDownIssuedAssignmentIDs
        let before = next
        aids.forEach { next.remove($0) }
        guard next != before else { return }
        squadCompletePolicyWindDownIssuedAssignmentIDs = next
    }

    internal func removeSquadAbortPolicyWindDownIssuedForBoundPrimaries(taskID: UUID) {
        guard let mission = template else { return }
        let aids = Set(primarySquads(forTaskID: taskID, mission: mission).map(\.assignment.id))
        guard !aids.isEmpty else { return }
        var next = squadAbortPolicyWindDownIssuedAssignmentIDs
        let before = next
        aids.forEach { next.remove($0) }
        guard next != before else { return }
        squadAbortPolicyWindDownIssuedAssignmentIDs = next
    }

    private func markPerSquadMissionEndRecoveryCompletedForBoundPrimaries(taskID: UUID) {
        guard let mission = template else { return }
        let aids = Set(primarySquads(forTaskID: taskID, mission: mission).map(\.assignment.id))
        guard !aids.isEmpty else { return }
        var done = squadMissionEndRecoveryCompletedByAssignmentIDs
        let before = done
        aids.forEach { done.insert($0) }
        if done != before { squadMissionEndRecoveryCompletedByAssignmentIDs = done }
        removeSquadCompletePolicyWindDownIssuedForBoundPrimaries(taskID: taskID)
    }

    private func markPerSquadMissionEndAbortCompletedForBoundPrimaries(taskID: UUID) {
        guard let mission = template else { return }
        let aids = Set(primarySquads(forTaskID: taskID, mission: mission).map(\.assignment.id))
        guard !aids.isEmpty else { return }
        var done = squadMissionEndAbortCompletedByAssignmentIDs
        let before = done
        aids.forEach { done.insert($0) }
        if done != before { squadMissionEndAbortCompletedByAssignmentIDs = done }
        removeSquadAbortPolicyWindDownIssuedForBoundPrimaries(taskID: taskID)
    }

    /// Records that §4 complete-policy fleet traffic for this primary row should open ``policyCompleting`` lanes without a task-wide issued marker.
    internal func markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID assignmentID: UUID) {
        guard !squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignmentID) else { return }
        var next = squadCompletePolicyWindDownIssuedAssignmentIDs
        next.insert(assignmentID)
        squadCompletePolicyWindDownIssuedAssignmentIDs = next
    }

    internal func markSquadAbortPolicyWindDownDispatchIssued(forAssignmentID assignmentID: UUID) {
        guard !squadAbortPolicyWindDownIssuedAssignmentIDs.contains(assignmentID) else { return }
        var next = squadAbortPolicyWindDownIssuedAssignmentIDs
        next.insert(assignmentID)
        squadAbortPolicyWindDownIssuedAssignmentIDs = next
    }

    // MARK: - MC-R → Live Drive operator handoff

    /// Records that MRE must not run autonomous work against this roster / pool row while Live Drive owns its stream.
    func noteOperatorLiveDriveHandoffActive(forAssignmentID assignmentID: UUID) {
        guard assignments.contains(where: { $0.id == assignmentID }) else { return }
        missionRunAssignmentIDsWithOperatorLiveDriveHandoff.insert(assignmentID)
    }

    func clearOperatorLiveDriveHandoff(forAssignmentID assignmentID: UUID) {
        guard missionRunAssignmentIDsWithOperatorLiveDriveHandoff.contains(assignmentID) else { return }
        var next = missionRunAssignmentIDsWithOperatorLiveDriveHandoff
        next.remove(assignmentID)
        missionRunAssignmentIDsWithOperatorLiveDriveHandoff = next
    }

    /// Clears every handoff marker whose roster row resolves to the same bridge ``vehicleID`` as MC‑R / Live Drive.
    func clearOperatorLiveDriveHandoffs(matchingResolvedFleetVehicleID vehicleID: String, fleetLink: FleetLinkService, sitl: SitlService) {
        guard !missionRunAssignmentIDsWithOperatorLiveDriveHandoff.isEmpty else { return }
        var removals: [UUID] = []
        for aid in missionRunAssignmentIDsWithOperatorLiveDriveHandoff {
            guard let row = assignments.first(where: { $0.id == aid }) else {
                removals.append(aid)
                continue
            }
            if resolvedFleetStreamVehicleID(assignment: row, fleetLink: fleetLink, sitl: sitl) == vehicleID {
                removals.append(aid)
            }
        }
        guard !removals.isEmpty else { return }
        var next = missionRunAssignmentIDsWithOperatorLiveDriveHandoff
        for r in removals { next.remove(r) }
        missionRunAssignmentIDsWithOperatorLiveDriveHandoff = next
    }

    /// Clears all MC‑R → Live Drive handoff markers when the run is no longer in the live envelope (e.g. completed or failed out).
    func clearOperatorLiveDriveHandoffsWhenRunFinished() {
        guard !missionRunAssignmentIDsWithOperatorLiveDriveHandoff.isEmpty else { return }
        missionRunAssignmentIDsWithOperatorLiveDriveHandoff = []
    }

    /// Per-task autostart suppress: issued wind-down / operator suppress set, pending per-task graceful rows, and Live Drive handoff task mapping.
    internal func unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission mission: Mission) -> Set<UUID> {
        var union = missionTaskAutopilotAutostartSuppressedTaskIDs
        union.formUnion(pendingMissionTaskGracefulWindDownKindByTaskID.keys)
        union.formUnion(missionTaskCompleteWindDownIssuedTaskIDs)
        union.formUnion(missionTaskAbortWindDownIssuedTaskIDs)
        guard !missionRunAssignmentIDsWithOperatorLiveDriveHandoff.isEmpty else { return union }
        for aid in missionRunAssignmentIDsWithOperatorLiveDriveHandoff {
            union.formUnion(missionTaskIDsForOperatorLiveDriveHandoffAssignment(id: aid, mission: mission))
        }
        return union
    }

    private func missionTaskIDsForOperatorLiveDriveHandoffAssignment(id assignmentID: UUID, mission: Mission) -> Set<UUID> {
        guard let assignment = assignments.first(where: { $0.id == assignmentID }) else { return [] }
        var s = Set<UUID>()
        if let tid = assignment.taskId {
            s.insert(tid)
        } else {
            let enabled = mission.routeMacro.tasks.filter(\.enabled)
            if enabled.count == 1, let only = enabled.first {
                s.insert(only.id)
            }
        }
        if let plan = compiledPlan {
            for tr in plan.roleTracks where tr.assignmentID == assignmentID {
                if let tid = tr.taskID { s.insert(tid) }
            }
        }
        return s
    }

    /// Operator marks this task’s MC-R lifecycle label as ``.aborted`` or ``.completed``; records that choice, emits one run event, and updates abort/recovery ack sets for session bookkeeping.
    func operatorMarkMissionTaskTriageState(taskID: UUID, state: MissionTaskState) {
        guard state == .aborted || state == .completed else { return }
        guard let mission = template, let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }) else { return }
        if operatorTriageMarkedMissionTaskStateByTaskID[taskID] == state { return }

        var triage = operatorTriageMarkedMissionTaskStateByTaskID
        triage[taskID] = state
        operatorTriageMarkedMissionTaskStateByTaskID = triage

        switch state {
        case .aborted:
            var abortDone = taskMissionEndAbortCompletedByTaskID
            abortDone.insert(taskID)
            taskMissionEndAbortCompletedByTaskID = abortDone
            var abortIssued = missionTaskAbortWindDownIssuedTaskIDs
            abortIssued.remove(taskID)
            missionTaskAbortWindDownIssuedTaskIDs = abortIssued
            var recoveryDone = taskMissionEndRecoveryCompletedByTaskID
            recoveryDone.remove(taskID)
            taskMissionEndRecoveryCompletedByTaskID = recoveryDone
            var completeIssued = missionTaskCompleteWindDownIssuedTaskIDs
            completeIssued.remove(taskID)
            missionTaskCompleteWindDownIssuedTaskIDs = completeIssued
            removeSquadCompletePolicyWindDownIssuedForBoundPrimaries(taskID: taskID)
        case .completed:
            var recoveryDone = taskMissionEndRecoveryCompletedByTaskID
            recoveryDone.insert(taskID)
            taskMissionEndRecoveryCompletedByTaskID = recoveryDone
            var completeIssued = missionTaskCompleteWindDownIssuedTaskIDs
            completeIssued.remove(taskID)
            missionTaskCompleteWindDownIssuedTaskIDs = completeIssued
            var abortDone = taskMissionEndAbortCompletedByTaskID
            abortDone.remove(taskID)
            taskMissionEndAbortCompletedByTaskID = abortDone
            var abortIssued = missionTaskAbortWindDownIssuedTaskIDs
            abortIssued.remove(taskID)
            missionTaskAbortWindDownIssuedTaskIDs = abortIssued
            removeSquadCompletePolicyWindDownIssuedForBoundPrimaries(taskID: taskID)
        default:
            break
        }

        clearMissionTaskEndAttemptStorage(forTaskID: taskID)

        appendEvent(
            MissionRunEvent(
                taskID: taskID,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.operatorMarkedMissionTaskTriageState,
                templateParams: [
                    "task": task.name,
                    "stateDisplay": state.displayTitle,
                ]
            )
        )

        let manualMessage = MissionRunSlotEvidenceAutoTriageOperatorCopy.toastManualTriage(taskName: task.name, state: state)
        if !manualMessage.isEmpty {
            GuardianMissionRunSlotEvidenceAutoTriageToastNotification.post(
                message: manualMessage,
                severity: state == .aborted ? .warning : .success
            )
        }

        refreshDerivedTaskStates()
    }

    // MARK: - §3 slot evidence → mission-end ack (auto triage)

    /// When **every** roster row bound to a task satisfies the §3 rollup for that task’s issued wind-down (strict
    /// ``policySucceeded`` for **abort**; settled terminals including ``policyFailed`` for **complete** — see
    /// ``MissionRunSlotEvidenceAutoMissionEndAckRules``), inserts the task into ``taskMissionEndAbortCompletedByTaskID`` or
    /// ``taskMissionEndRecoveryCompletedByTaskID`` **without** an operator triage pin (``TaskRosterAssignmentStatesToDo.md`` §3).
    ///
    /// Call after §3 push/pull lane mutations for the listed ``MissionRunAssignment/id`` values. Emits **one** consolidated
    /// run log line per invocation and posts ``GuardianMissionRunSlotEvidenceAutoTriageToastNotification`` with the same batch summary.
    internal func applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs assignmentIDs: Set<UUID>) {
        guard allowsMissionEndAutoSettlement else { return }
        guard let mission = template else { return }
        var squadStatesDirty = false
        for aid in assignmentIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            if tryApplyPerSquadAutoMissionEndAckIfNeeded(assignmentID: aid, mission: mission) {
                squadStatesDirty = true
            }
        }
        var taskIDs = Set<UUID>()
        for aid in assignmentIDs {
            guard let assignment = assignments.first(where: { $0.id == aid }) else { continue }
            if let tid = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission) {
                taskIDs.insert(tid)
            }
        }
        var abortTaskNames: [String] = []
        var recoveryTaskNames: [String] = []
        for tid in taskIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let outcome = trySlotEvidenceAutoMissionEndAckMutation(forTaskID: tid, mission: mission) else { continue }
            switch outcome {
            case .abort(let name):
                abortTaskNames.append(name)
            case .recovery(let name):
                recoveryTaskNames.append(name)
            }
        }
        if squadStatesDirty { refreshDerivedSquadStates() }
        guard !abortTaskNames.isEmpty || !recoveryTaskNames.isEmpty else { return }
        appendSlotEvidenceAutoAckConsolidatedMissionRunEvent(abortTaskNames: abortTaskNames, recoveryTaskNames: recoveryTaskNames)
        postSlotEvidenceAutoTriageToast(abortTaskNames: abortTaskNames, recoveryTaskNames: recoveryTaskNames)
        refreshDerivedTaskStates()
    }

    /// Per-primary-squad §3 ack when wind-down was squad-scoped (operator Continue retry, finite per-squad complete) without task-wide issued markers.
    @discardableResult
    private func tryApplyPerSquadAutoMissionEndAckIfNeeded(assignmentID: UUID, mission: Mission) -> Bool {
        guard let assignment = assignments.first(where: { $0.id == assignmentID }),
              let taskID = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }),
              task.enabled,
              primarySquads(forTaskID: taskID, mission: mission).contains(where: { $0.assignment.id == assignmentID })
        else { return false }
        guard operatorTriageMarkedMissionTaskStateByTaskID[taskID] == nil else { return false }

        if squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignmentID) {
            guard !squadMissionEndRecoveryCompletedByAssignmentIDs.contains(assignmentID) else { return false }
            guard MissionRunSlotEvidenceAutoMissionEndAckRules.mergedSlotSettledForCompleteMissionEndAutoAck(assignment) else { return false }
            markSquadMissionEndRecoveryCompleted(forAssignmentID: assignmentID)
            var issued = squadCompletePolicyWindDownIssuedAssignmentIDs
            issued.remove(assignmentID)
            squadCompletePolicyWindDownIssuedAssignmentIDs = issued
            return true
        }

        if squadAbortPolicyWindDownIssuedAssignmentIDs.contains(assignmentID) {
            guard !squadMissionEndAbortCompletedByAssignmentIDs.contains(assignmentID) else { return false }
            guard MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: assignment.effectiveSlotLifecycleLanes) == .policySucceeded else { return false }
            markSquadMissionEndAbortCompleted(forAssignmentID: assignmentID)
            var issued = squadAbortPolicyWindDownIssuedAssignmentIDs
            issued.remove(assignmentID)
            squadAbortPolicyWindDownIssuedAssignmentIDs = issued
            return true
        }

        return false
    }

    private enum SlotEvidenceAutoMissionEndAckMutationOutcome {
        case abort(String)
        case recovery(String)
    }

    /// Returns an outcome only when this call **mutated** ack / issued sets (idempotent replays return `nil`).
    private func trySlotEvidenceAutoMissionEndAckMutation(
        forTaskID taskID: UUID,
        mission: Mission
    ) -> SlotEvidenceAutoMissionEndAckMutationOutcome? {
        if operatorTriageMarkedMissionTaskStateByTaskID[taskID] != nil { return nil }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }), task.enabled else { return nil }
        let bound = assignmentsBoundToMissionTask(taskID: taskID)

        if missionTaskAbortWindDownIssuedTaskIDs.contains(taskID) {
            guard MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded(bound) else { return nil }
            guard insertAutoMissionEndAbortAckIfNeeded(taskID: taskID) else { return nil }
            return .abort(task.name)
        }
        if Self.allPrimariesHavePerSquadAbortCompleted(task: task, run: self, mission: mission) {
            guard MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded(bound) else { return nil }
            guard insertAutoMissionEndAbortAckIfNeeded(taskID: taskID) else { return nil }
            return .abort(task.name)
        }
        let completeRecoveryIntent = missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID)
            || Self.allPrimariesDispatchedPerSquadCompletePolicyWindDown(task: task, run: self)
            || Self.allPrimariesHavePerSquadRecoveryCompleted(task: task, run: self, mission: mission)
        if completeRecoveryIntent {
            guard MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsSatisfiedForCompleteMissionEndAutoAck(bound) else { return nil }
            guard insertAutoMissionEndRecoveryAckIfNeeded(taskID: taskID) else { return nil }
            return .recovery(task.name)
        }
        return nil
    }

    private func appendSlotEvidenceAutoAckConsolidatedMissionRunEvent(abortTaskNames: [String], recoveryTaskNames: [String]) {
        let abortJoined = abortTaskNames.joined(separator: ", ")
        let recoveryJoined = recoveryTaskNames.joined(separator: ", ")
        appendEvent(
            MissionRunEvent(
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.slotEvidenceAutoAcknowledgedMissionEndBatch,
                templateParams: [
                    "abortTasks": abortJoined.isEmpty ? "—" : abortJoined,
                    "recoveryTasks": recoveryJoined.isEmpty ? "—" : recoveryJoined,
                ]
            )
        )
    }

    private func postSlotEvidenceAutoTriageToast(abortTaskNames: [String], recoveryTaskNames: [String]) {
        GuardianMissionRunSlotEvidenceAutoTriageToastNotification.post(
            message: MissionRunSlotEvidenceAutoTriageOperatorCopy.toastConsolidated(
                abortTaskNames: abortTaskNames,
                recoveryTaskNames: recoveryTaskNames
            ),
            severity: .success
        )
    }

    /// `true` when state changed (first auto-ack for this task on this protocol).
    @discardableResult
    private func insertAutoMissionEndAbortAckIfNeeded(taskID: UUID) -> Bool {
        guard !taskMissionEndAbortCompletedByTaskID.contains(taskID) else { return false }
        var abortDone = taskMissionEndAbortCompletedByTaskID
        abortDone.insert(taskID)
        taskMissionEndAbortCompletedByTaskID = abortDone
        var abortIssued = missionTaskAbortWindDownIssuedTaskIDs
        abortIssued.remove(taskID)
        missionTaskAbortWindDownIssuedTaskIDs = abortIssued
        var recoveryDone = taskMissionEndRecoveryCompletedByTaskID
        recoveryDone.remove(taskID)
        taskMissionEndRecoveryCompletedByTaskID = recoveryDone
        var completeIssued = missionTaskCompleteWindDownIssuedTaskIDs
        completeIssued.remove(taskID)
        missionTaskCompleteWindDownIssuedTaskIDs = completeIssued
        clearMissionTaskEndAttemptStorage(forTaskID: taskID)
        markPerSquadMissionEndAbortCompletedForBoundPrimaries(taskID: taskID)
        return true
    }

    /// `true` when state changed (first auto-ack for this task on this protocol).
    @discardableResult
    private func insertAutoMissionEndRecoveryAckIfNeeded(taskID: UUID) -> Bool {
        guard !taskMissionEndRecoveryCompletedByTaskID.contains(taskID) else { return false }
        var recoveryDone = taskMissionEndRecoveryCompletedByTaskID
        recoveryDone.insert(taskID)
        taskMissionEndRecoveryCompletedByTaskID = recoveryDone
        var completeIssued = missionTaskCompleteWindDownIssuedTaskIDs
        completeIssued.remove(taskID)
        missionTaskCompleteWindDownIssuedTaskIDs = completeIssued
        var abortDone = taskMissionEndAbortCompletedByTaskID
        abortDone.remove(taskID)
        taskMissionEndAbortCompletedByTaskID = abortDone
        var abortIssued = missionTaskAbortWindDownIssuedTaskIDs
        abortIssued.remove(taskID)
        missionTaskAbortWindDownIssuedTaskIDs = abortIssued
        clearMissionTaskEndAttemptStorage(forTaskID: taskID)
        markPerSquadMissionEndRecoveryCompletedForBoundPrimaries(taskID: taskID)
        return true
    }

    private static func allPrimariesHavePerSquadRecoveryCompleted(
        task: MissionTask,
        run: MissionRunEnvironment,
        mission: Mission
    ) -> Bool {
        let primaries = run.primarySquads(forTaskID: task.id, mission: mission)
        guard !primaries.isEmpty else { return false }
        return primaries.allSatisfy { run.squadMissionEndRecoveryCompletedByAssignmentIDs.contains($0.assignment.id) }
    }

    private static func allPrimariesHavePerSquadAbortCompleted(
        task: MissionTask,
        run: MissionRunEnvironment,
        mission: Mission
    ) -> Bool {
        let primaries = run.primarySquads(forTaskID: task.id, mission: mission)
        guard !primaries.isEmpty else { return false }
        return primaries.allSatisfy { run.squadMissionEndAbortCompletedByAssignmentIDs.contains($0.assignment.id) }
    }

    @discardableResult
    func abortMissionTask(_ target: MissionRunCommandTarget) -> Bool {
        switch target {
        case .task, .squad: break
        }
        guard status == .running || status == .paused else { return false }
        guard sessionPhase == .executing else { return false }
        guard let ctx = effectiveExecutionContextForDispatch() else {
            systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.abortMissionTaskNoDispatchContext
            )
            return false
        }
        captureExecutionContext(ctx)
        return systems.scheduling.abortMissionTaskNow(target: target, context: ctx)
    }

    @discardableResult
    func abortMissionTaskGraceful(_ target: MissionRunCommandTarget) -> Bool {
        guard status == .running || status == .paused else { return false }
        guard sessionPhase == .executing else { return false }
        return systems.scheduling.abortMissionTaskAfterCycle(target: target)
    }

    @discardableResult
    func completeMissionTask(_ target: MissionRunCommandTarget) -> Bool {
        switch target {
        case .task, .squad: break
        }
        guard status == .running || status == .paused else { return false }
        guard sessionPhase == .executing else { return false }
        guard let ctx = effectiveExecutionContextForDispatch() else {
            systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.completeMissionTaskNoDispatchContext
            )
            return false
        }
        captureExecutionContext(ctx)
        return systems.scheduling.completeMissionTaskNow(target: target, context: ctx)
    }

    @discardableResult
    func completeMissionTaskGraceful(_ target: MissionRunCommandTarget) -> Bool {
        guard status == .running || status == .paused else { return false }
        guard sessionPhase == .executing else { return false }
        return systems.scheduling.completeMissionTaskAfterCycle(target: target)
    }

    /// Cancels a previously scheduled per-task end-of-cycle wind-down for one task (or all tasks if `taskID` is nil).
    func revokeMissionTaskGracefulWindDown(forTaskID taskID: UUID? = nil) {
        systems.scheduling.revokeMissionTaskGracefulWindDown(forTaskID: taskID)
    }

    /// Cancels scheduled end-of-cycle wind-down for one primary squad only.
    func revokeMissionSquadGracefulWindDown(forAssignmentID assignmentID: UUID) {
        clearPendingMissionSquadGracefulWindDown(forAssignmentID: assignmentID)
    }

    func installAssistant(_ assistant: AnyObject, key: String) {
        assistantsByKey[key] = assistant
        if let planningAssistant = assistant as? MissionRunPlanningAssistant {
            systems.planner.registerPlanningCallback(key: key) { [weak planningAssistant] run, mission, fleetVehicles, plan in
                guard let planningAssistant else { return plan }
                return planningAssistant.missionRun(
                    run,
                    planning: mission,
                    fleetVehicles: fleetVehicles,
                    applyingTo: plan
                )
            }
        }
        if let mutationAssistant = assistant as? MissionRunPlanningMutationAssistant {
            systems.planner.registerMutationProposalCallback(key: key) { [weak mutationAssistant] run, mission, fleetVehicles, mutation in
                guard let mutationAssistant else { return mutation }
                return mutationAssistant.missionRun(
                    run,
                    planning: mission,
                    fleetVehicles: fleetVehicles,
                    shouldApply: mutation
                )
            }
            systems.planner.registerMutationCommitCallback(key: key) { [weak mutationAssistant] run, mission, fleetVehicles, result in
                guard let mutationAssistant else { return }
                mutationAssistant.missionRun(
                    run,
                    planning: mission,
                    fleetVehicles: fleetVehicles,
                    didApply: result
                )
            }
        }
        if let abortAssistant = assistant as? MissionRunAbortPlanningAssistant {
            systems.planner.registerAbortPlanCallback(key: key) { [weak abortAssistant] run, plan in
                guard let abortAssistant else { return plan }
                return abortAssistant.missionRun(run, adjustingAbortPlan: plan)
            }
        }
    }

    func removeAssistant(forKey key: String) {
        assistantsByKey.removeValue(forKey: key)
        systems.planner.unregisterPlanningCallback(key: key)
        systems.planner.unregisterMutationProposalCallback(key: key)
        systems.planner.unregisterMutationCommitCallback(key: key)
        systems.planner.unregisterAbortPlanCallback(key: key)
    }

    func assistant<T>(forKey key: String, as type: T.Type = T.self) -> T? {
        assistantsByKey[key] as? T
    }

    func updateTemplate(_ mission: Mission?) {
        self.template = mission
        if let mission {
            missionId = mission.id
            missionName = mission.name
            syncRosterRoleResolutions(from: mission)
            syncRuntimeMissionPointsFromTemplate(mission, reason: .templateRefresh)
            pruneReservePoolsToMatchTasks(in: mission)
        } else {
            rosterRoleResolutionsByDeviceID = [:]
            runtimeMissionPoints = []
            reservePoolByTaskID = [:]
            reservePoolBulkSimHomeByTaskID = [:]
            operatorLaunchPoseByAssignmentID = [:]
            pendingMCSLaunchCaptureOverridesByAssignmentID = [:]
            rosterSimStartPoseSnapshotByAssignmentID = [:]
            reservePoolSimStartPoseSnapshotBySlotID = [:]
            writtenOffFleetVehicleStorageKeysForReservePool = []
        }
        pruneOperatorLaunchPosesToCurrentAssignments()
        pruneRosterSimStartPoseSnapshotsToCurrentAssignments()
        pruneReservePoolSimStartPoseSnapshotsToCurrentSlots()
        refreshDerivedTaskStates()
    }

    // MARK: - Operator launch pose (MCS Start Run → Return to Launch)

    private func pruneOperatorLaunchPosesToCurrentAssignments() {
        let valid = Set(assignments.map(\.id))
        let pruned = operatorLaunchPoseByAssignmentID.filter { valid.contains($0.key) }
        guard pruned.count != operatorLaunchPoseByAssignmentID.count else { return }
        operatorLaunchPoseByAssignmentID = pruned
    }

    func clearOperatorLaunchPoses(forAssignmentIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var m = operatorLaunchPoseByAssignmentID
        var touched = false
        for id in ids {
            if m.removeValue(forKey: id) != nil { touched = true }
        }
        guard touched else { return }
        operatorLaunchPoseByAssignmentID = m
    }

    /// Unit tests only: replaces ``operatorLaunchPoseByAssignmentID``.
    internal func unitTestingReplaceOperatorLaunchPoses(_ next: [UUID: FleetSimState]) {
        operatorLaunchPoseByAssignmentID = next
    }

    /// Records each bound roster row's MCS pose at **Start Run** (hub telemetry, optional staging-map override).
    func captureOperatorLaunchPosesAtRunStart(fleetLink: FleetLinkService, sitl: SitlService) {
        let overrides = pendingMCSLaunchCaptureOverridesByAssignmentID
        pendingMCSLaunchCaptureOverridesByAssignmentID = [:]
        var next: [UUID: FleetSimState] = [:]
        for assignment in assignments {
            guard assignment.hasFleetOrLegacyAssignment else { continue }
            guard let raw = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let token = FleetMissionVehicleToken(storageKey: raw),
                  let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
            else { continue }
            let hub = fleetLink.hubTelemetryByVehicleID[vehicleID]
            if let override = overrides[assignment.id] {
                let alt = hub?.absoluteAltM ?? hub?.altitudeAmslM
                let heading = hub?.headingDeg ?? hub?.yawDeg ?? 0
                next[assignment.id] = FleetSimState(
                    latitudeDeg: override.lat,
                    longitudeDeg: override.lon,
                    absoluteAltitudeM: alt,
                    yawDeg: Float(heading),
                    batteryVoltageV: nil,
                    ardupilotSimBattCapAh: nil,
                    px4SimBatDrain: nil
                )
                continue
            }
            guard let hub, let snap = FleetSimState(simHomeRestoreSnapshotFrom: hub) else { continue }
            next[assignment.id] = snap
        }
        operatorLaunchPoseByAssignmentID = next
    }

    /// Return to Launch / Go Home dispatch for one roster row (move+park to MCS launch, else stack RTL).
    func returnToLaunchFleetDispatch(
        assignmentID: UUID,
        planningHub: FleetHubVehicleTelemetry?
    ) -> MissionRunFleetDispatch {
        let relAlt = planningHub?.guardianAbortPlanningRelativeAltitudeM ?? 0
        return MissionControlOperatorLaunchPosePolicy.resolvedReturnToLaunchDispatch(
            assignmentID: assignmentID,
            launchPoseByAssignmentID: operatorLaunchPoseByAssignmentID,
            planningRelativeAltitudeM: relAlt
        )
    }

    // MARK: - Roster SIM start pose (run-complete home reset, v1)

    private func pruneRosterSimStartPoseSnapshotsToCurrentAssignments() {
        let valid = Set(assignments.map(\.id))
        let pruned = rosterSimStartPoseSnapshotByAssignmentID.filter { valid.contains($0.key) }
        guard pruned.count != rosterSimStartPoseSnapshotByAssignmentID.count else { return }
        rosterSimStartPoseSnapshotByAssignmentID = pruned
    }

    private func pruneReservePoolSimStartPoseSnapshotsToCurrentSlots() {
        var valid: Set<UUID> = []
        for (_, pool) in reservePoolByTaskID {
            for slot in pool.entries {
                valid.insert(slot.id)
            }
        }
        let pruned = reservePoolSimStartPoseSnapshotBySlotID.filter { valid.contains($0.key) }
        guard pruned.count != reservePoolSimStartPoseSnapshotBySlotID.count else { return }
        reservePoolSimStartPoseSnapshotBySlotID = pruned
    }

    /// Drops captured SIM poses for the given roster rows (e.g. planner fleet binding change or roster swap).
    func clearRosterSimStartPoseSnapshots(forAssignmentIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var m = rosterSimStartPoseSnapshotByAssignmentID
        var touched = false
        for id in ids {
            if m.removeValue(forKey: id) != nil { touched = true }
        }
        guard touched else { return }
        rosterSimStartPoseSnapshotByAssignmentID = m
    }

    /// Drops captured pool SIM poses when a berth binding changes or the row is removed.
    func clearReservePoolSimStartPoseSnapshots(forSlotIDs ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var m = reservePoolSimStartPoseSnapshotBySlotID
        var touched = false
        for id in ids {
            if m.removeValue(forKey: id) != nil { touched = true }
        }
        guard touched else { return }
        reservePoolSimStartPoseSnapshotBySlotID = m
    }

    /// Unit tests only: replaces ``rosterSimStartPoseSnapshotByAssignmentID`` (production callers use capture / prune / clear APIs).
    internal func unitTestingReplaceRosterSimStartPoseSnapshots(_ next: [UUID: FleetSimState]) {
        rosterSimStartPoseSnapshotByAssignmentID = next
    }

    /// Unit tests only: replaces ``reservePoolSimStartPoseSnapshotBySlotID``.
    internal func unitTestingReplaceReservePoolSimStartPoseSnapshots(_ next: [UUID: FleetSimState]) {
        reservePoolSimStartPoseSnapshotBySlotID = next
    }

    /// Captures hub SIM pose per **SITL** roster binding the **first** time this run starts execution (README → SIM home reset).
    /// Also captures **floating reserve pool** SITL poses per slot (incremental: new bindings after earlier starts still snapshot before run-complete restore).
    func captureRosterSimStartPoseSnapshotsIfNeeded(fleetLink: FleetLinkService, sitl: SitlService) {
        if rosterSimStartPoseSnapshotByAssignmentID.isEmpty {
            var rosterNext: [UUID: FleetSimState] = [:]
            for assignment in assignments {
                guard assignment.hasFleetOrLegacyAssignment else { continue }
                guard let raw = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty,
                      let token = FleetMissionVehicleToken(storageKey: raw),
                      let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
                else { continue }
                guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else { continue }
                guard let hub = fleetLink.hubTelemetryByVehicleID[vehicleID],
                      let snap = FleetSimState(simHomeRestoreSnapshotFrom: hub)
                else { continue }
                rosterNext[assignment.id] = snap
            }
            if !rosterNext.isEmpty {
                rosterSimStartPoseSnapshotByAssignmentID = rosterNext
            }
        }

        var poolMap = reservePoolSimStartPoseSnapshotBySlotID
        var poolTouched = false
        let orderedTaskIDs = reservePoolByTaskID.keys.sorted { $0.uuidString < $1.uuidString }
        for taskID in orderedTaskIDs {
            guard let pool = reservePoolByTaskID[taskID] else { continue }
            let bulk = reservePoolBulkSimHomeByTaskID[taskID]
            for slot in pool.entries {
                guard MCSReservePoolHomeStagingMapEligibility.isEligibleSitlReservePoolSlot(
                    slot: slot,
                    sitl: sitl,
                    fleetLink: fleetLink
                ) else { continue }
                guard poolMap[slot.id] == nil else { continue }
                guard let raw = slot.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty,
                      let token = FleetMissionVehicleToken(storageKey: raw),
                      let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
                else { continue }
                guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else { continue }
                let hub = fleetLink.hubTelemetryByVehicleID[vehicleID]
                guard let snap = FleetSimState(reservePoolSimHomeRestoreStartPose: hub, bulkHome: bulk) else { continue }
                poolMap[slot.id] = snap
                poolTouched = true
            }
        }
        if poolTouched {
            reservePoolSimStartPoseSnapshotBySlotID = poolMap
        }
    }

    /// Looks up a floating reserve pool slot by stable id (for SIM cleanup / restore).
    internal func reservePoolSlot(forSlotID slotID: UUID) -> (taskID: UUID, slot: MissionRunReservePoolSlot)? {
        for (taskID, pool) in reservePoolByTaskID {
            if let slot = pool.entries.first(where: { $0.id == slotID }) {
                return (taskID, slot)
            }
        }
        return nil
    }

    // MARK: - Floating reserve pool (MCS / MRE)

    func setReservePool(_ pool: MissionRunReservePool, forTaskID taskID: UUID) {
        var next = reservePoolByTaskID
        next[taskID] = pool
        reservePoolByTaskID = next
        pruneReservePoolSimStartPoseSnapshotsToCurrentSlots()
    }

    func clearReservePool(forTaskID taskID: UUID) {
        var next = reservePoolByTaskID
        next.removeValue(forKey: taskID)
        reservePoolByTaskID = next
        pruneReservePoolSimStartPoseSnapshotsToCurrentSlots()
    }

    /// Appends one **slot** to the task’s pool without rewriting unrelated slots. Returns the slot’s stable ``MissionRunReservePoolSlot/id``.
    @discardableResult
    func appendReservePoolSlot(_ slot: MissionRunReservePoolSlot, forTaskID taskID: UUID) -> UUID {
        var pool = reservePool(forTaskID: taskID)
        pool.entries.append(slot)
        var next = reservePoolByTaskID
        next[taskID] = pool
        reservePoolByTaskID = next
        return slot.id
    }

    /// Removes the slot with ``slotID`` from the task’s pool. Drops the task key when the pool becomes empty.
    @discardableResult
    func removeReservePoolSlot(id slotID: UUID, forTaskID taskID: UUID) -> Bool {
        var pool = reservePool(forTaskID: taskID)
        let before = pool.entries.count
        pool.entries.removeAll { $0.id == slotID }
        guard pool.entries.count != before else { return false }
        clearReservePoolSimStartPoseSnapshots(forSlotIDs: [slotID])
        var next = reservePoolByTaskID
        if pool.entries.isEmpty {
            next.removeValue(forKey: taskID)
        } else {
            next[taskID] = pool
        }
        reservePoolByTaskID = next
        return true
    }

    /// Replaces the slot keyed by ``slotID`` in place (stable id). Payload is taken from ``replacement`` except **id**, which stays ``slotID``.
    @discardableResult
    func replaceReservePoolSlot(id slotID: UUID, forTaskID taskID: UUID, with replacement: MissionRunReservePoolSlot) -> Bool {
        var pool = reservePool(forTaskID: taskID)
        guard let idx = pool.entries.firstIndex(where: { $0.id == slotID }) else { return false }
        clearReservePoolSimStartPoseSnapshots(forSlotIDs: [slotID])
        pool.entries[idx] = MissionRunReservePoolSlot(
            id: slotID,
            label: replacement.label,
            attachedFleetVehicleToken: replacement.attachedFleetVehicleToken,
            attachedDevice: replacement.attachedDevice
        )
        var next = reservePoolByTaskID
        next[taskID] = pool
        reservePoolByTaskID = next
        return true
    }

    func reservePool(forTaskID taskID: UUID) -> MissionRunReservePool {
        reservePoolByTaskID[taskID] ?? MissionRunReservePool()
    }

    /// `true` when any floating reserve pool berth on this run holds this fleet vehicle storage key (trimmed; empty / whitespace-only is never held).
    func reservePoolContainsFleetVehicleStorageKey(_ storageKey: String) -> Bool {
        let key = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        for (_, pool) in reservePoolByTaskID {
            for slot in pool.entries {
                let tok = (slot.attachedFleetVehicleToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if tok == key { return true }
            }
        }
        return false
    }

    /// Filled reserve **slots** MRE may choose from on ``taskID``: has binding, fleet token not run-written-off, and when
    /// ``fleetLink`` + ``sitl`` are attached, the bound vehicle must resolve and pass the same **lifecycle + battery** gate
    /// as ``returnAssignmentToReservePool`` (``FleetVehicleOperationalModel/qualifiesForMissionRunReservePoolOperationalDraw``).
    /// **Roster slot chip state is out of scope:** ``MissionRunAssignment/slotLifecycleLanes`` on the **vacancy** or other rows does not filter pool entries here.
    /// Legacy text-only slots stay eligible whenever they have a non-empty device string. If services are not attached yet,
    /// only binding + written-off rules apply (MCS setup before link).
    ///
    /// When ``classCompatibleWithAssignmentId`` is set, slots whose resolved fleet type does not satisfy the roster row’s
    /// template ``RosterDevice/vehicleClass`` (via ``FleetVehicleType/substitutionMatches`` / ``FleetVehicleSubstitutionPolicy/missionRunReserveSwap``)
    /// are dropped. Template class ``unknown`` applies **no** class filter. Slots without a resolvable typed fleet binding are
    /// dropped when the vacancy is typed.
    func availableReservePoolEntries(
        forTaskID taskID: UUID,
        classCompatibleWithAssignmentId assignmentId: UUID? = nil
    ) -> [MissionRunReservePoolEntry] {
        var rows = reservePool(forTaskID: taskID).entries.filter { slot in
            isReservePoolSlotEligibleForRandomPick(slot) && passesReservePoolSlotOperationalDrawGate(slot)
        }
        if let aid = assignmentId,
           let assignment = assignments.first(where: { $0.id == aid }) {
            let expected = expectedFleetVehicleClassForRosterAssignment(assignment)
            rows = rows.filter { reservePoolSlotMatchesVacancyClass(expected: expected, slot: $0) }
        }
        return rows
    }

    /// Candidates to **replace** the roster binding at ``vacancyAssignmentID`` on ``taskID``: **class-compatible** floating pool rows
    /// (same rules as ``availableReservePoolEntries(forTaskID:classCompatibleWithAssignmentId:)``), excluding any pool berth whose fleet token
    /// equals the vacancy’s current token; plus same-task template ``MissionRosterSlotRole/reserve`` roster rows with a binding that passes the
    /// same **class**, **written-off**, and **reserve-pool-style operational** gates as pool draws.
    ///
    /// **Ordering:** controlled by ``ordering``. With ``MissionRunReserveSwapCandidateOrdering/poolSlotsFirst`` (default): pool entries in slot list order, then sorted roster reserve rows — **MC-R** pickers and operator surfaces. With ``MissionRunReserveSwapCandidateOrdering/fixedRosterReservesFirst``: same two slices, but **fixed template reserves first**, then pool (autonomous / headless callers that walk the array in order). **Primary** (and non-wingman) vacancies: fixed reserves sorted by ``MissionRunAssignment/slotName`` then ``id``. **Wingman** vacancies: fixed reserves with ``RosterDevice/leaderRosterDeviceId`` equal to this wingman’s **primary** first (explicit link, or the sole task primary when the wingman has no leader id); then reserves with **no** leader id (**auto**); then reserves tied to another primary — each band sorted by ``slotName`` then ``id``.
    /// ``swapRosterAssignmentWithRandomFloatingReserve`` continues to use pool-only selection; this API feeds pickers / automation / swap-in phases.
    func enumerateReserveSwapCandidates(
        vacancyAssignmentID: UUID,
        taskID: UUID,
        ordering: MissionRunReserveSwapCandidateOrdering = .poolSlotsFirst
    ) -> [MissionRunReserveSwapCandidate] {
        guard let vacancy = assignments.first(where: { $0.id == vacancyAssignmentID }),
              assignmentsBoundToMissionTask(taskID: taskID).contains(where: { $0.id == vacancyAssignmentID })
        else { return [] }

        let vacancyToken = Self.normalizedFleetStorageKey(vacancy.attachedFleetVehicleToken)
        var poolOut: [MissionRunReserveSwapCandidate] = []

        for slot in availableReservePoolEntries(forTaskID: taskID, classCompatibleWithAssignmentId: vacancyAssignmentID) {
            let slotToken = Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken)
            if !vacancyToken.isEmpty, slotToken == vacancyToken { continue }
            poolOut.append(.floatingPool(taskID: taskID, slot: slot))
        }

        let rosterByID = Dictionary(uniqueKeysWithValues: (template?.rosterDevices ?? []).map { ($0.id, $0) })
        let expected = expectedFleetVehicleClassForRosterAssignment(vacancy)

        var rosterRows: [MissionRunAssignment] = []
        for candidate in assignmentsBoundToMissionTask(taskID: taskID) {
            guard candidate.id != vacancyAssignmentID else { continue }
            guard let rd = rosterByID[candidate.rosterDeviceId], rd.slot == .reserve else { continue }
            guard candidate.hasFleetOrLegacyAssignment else { continue }

            let candidateToken = Self.normalizedFleetStorageKey(candidate.attachedFleetVehicleToken)
            if !vacancyToken.isEmpty, candidateToken == vacancyToken { continue }
            if !candidateToken.isEmpty, isFleetVehicleWrittenOffForReservePool(storageKey: candidateToken) { continue }
            if !candidateToken.isEmpty, !missionRunFleetBindingPassesReservePoolOperationalDrawGate(fleetStorageKey: candidateToken) {
                continue
            }
            guard rosterReserveFleetBindingMatchesVacancyClass(expected: expected, assignment: candidate) else { continue }
            rosterRows.append(candidate)
        }
        sortFixedReserveAssignmentsForReserveSwapEnumerate(
            &rosterRows,
            vacancy: vacancy,
            rosterByID: rosterByID,
            taskID: taskID,
            mission: template
        )
        let fixedOut: [MissionRunReserveSwapCandidate] = rosterRows.map { .fixedRosterReserve(assignment: $0) }
        switch ordering {
        case .poolSlotsFirst:
            return poolOut + fixedOut
        case .fixedRosterReservesFirst:
            return fixedOut + poolOut
        }
    }

    /// MC-R floating pool **reserve swap pick** strip: operator-facing title + subtitle when ``enumerateReserveSwapCandidates`` has **no** pool rows (`MissionLiveVehicleHealthCard` empty state).
    ///
    /// Returns `nil` when at least one floating pool candidate exists (caller should not show the empty card).
    func floatingReservePoolPickStripEmptyOperatorCopy(
        vacancyAssignmentID: UUID,
        taskID: UUID
    ) -> (title: String, subtitle: String)? {
        let poolCandidateSlots: [MissionRunReservePoolSlot] = enumerateReserveSwapCandidates(
            vacancyAssignmentID: vacancyAssignmentID,
            taskID: taskID,
            ordering: .poolSlotsFirst
        ).compactMap { candidate in
            if case .floatingPool(let tid, let slot) = candidate, tid == taskID { return slot }
            return nil
        }
        guard poolCandidateSlots.isEmpty else { return nil }
        guard let vacancy = assignments.first(where: { $0.id == vacancyAssignmentID }) else {
            return ("No eligible reserves", "This roster slot is unavailable for reserve swap.")
        }

        let pool = reservePool(forTaskID: taskID).entries
        func appendBenchHint(_ subtitle: String) -> String {
            let hasBench = enumerateReserveSwapCandidates(
                vacancyAssignmentID: vacancyAssignmentID,
                taskID: taskID,
                ordering: .poolSlotsFirst
            ).contains { cand in
                if case .fixedRosterReserve = cand { return true }
                return false
            }
            if hasBench {
                return subtitle + " A template reserve row on this task may still work."
            }
            return subtitle
        }

        if pool.isEmpty {
            return ("No reserve berths", appendBenchHint("Add floating reserve slots in Mission Control setup."))
        }
        let anyBinding = pool.contains { $0.hasFleetOrLegacyBinding }
        if !anyBinding {
            return ("No bound reserves", appendBenchHint("Bind vehicles to floating reserve berths on this task."))
        }

        let slotsWithNonEmptyFleetToken = pool.filter { slot in
            guard slot.hasFleetOrLegacyBinding else { return false }
            return !Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken).isEmpty
        }
        if !slotsWithNonEmptyFleetToken.isEmpty,
           slotsWithNonEmptyFleetToken.allSatisfy({
               isFleetVehicleWrittenOffForReservePool(storageKey: Self.normalizedFleetStorageKey($0.attachedFleetVehicleToken))
           })
        {
            return (
                "No eligible reserves",
                appendBenchHint("All floating reserve vehicles on this task are written off for this run.")
            )
        }

        let vacTok = Self.normalizedFleetStorageKey(vacancy.attachedFleetVehicleToken)
        let classOK = availableReservePoolEntries(forTaskID: taskID, classCompatibleWithAssignmentId: vacancyAssignmentID)
        let classIgnore = availableReservePoolEntries(forTaskID: taskID, classCompatibleWithAssignmentId: nil)

        func dedupeVacancyToken(_ rows: [MissionRunReservePoolEntry]) -> [MissionRunReservePoolEntry] {
            rows.filter { slot in
                let st = Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken)
                return vacTok.isEmpty || st != vacTok
            }
        }
        let classIgnoreDeduped = dedupeVacancyToken(classIgnore)
        let classOKDeduped = dedupeVacancyToken(classOK)

        if classIgnore.isEmpty {
            return (
                "No eligible reserves",
                appendBenchHint("Pool vehicles on this task cannot be drawn (written off for floating reserve on this run, battery or lifecycle, or hub link).")
            )
        }
        if classIgnoreDeduped.isEmpty {
            return (
                "No other reserves",
                appendBenchHint("Every pool vehicle already shares this slot’s fleet binding.")
            )
        }
        if classOKDeduped.isEmpty {
            if classOK.isEmpty {
                let expected = expectedFleetVehicleClassForRosterAssignment(vacancy)
                return (
                    "No matching reserves",
                    appendBenchHint("No floating reserve matches this slot’s class (\(expected.classCode) · \(expected.displayName)).")
                )
            } else {
                return (
                    "No other reserves",
                    appendBenchHint("Every class-matched pool vehicle already shares this slot’s fleet binding.")
                )
            }
        }

        return (
            "No eligible reserves",
            appendBenchHint("Add or bind a class-compatible floating reserve on this task.")
        )
    }

    /// Append a structured ``MissionRunReserveSwapPhaseLogTemplateKey`` line (`missioncontrol.mre.reserve.phase.*`).
    func appendReserveSwapPipelinePhaseLog(
        phase: MissionRunReserveSwapPipelinePhase,
        passed: Bool,
        correlation: MissionRunReserveRecipeRunnerCorrelation,
        detail: String,
        recipeRaw: String? = nil
    ) {
        let taskLabel = template?.routeMacro.tasks.first(where: { $0.id == correlation.missionTaskID })?.name
        systems.logging.appendLogEvent(
            level: passed ? .info : .warning,
            taskID: correlation.missionTaskID,
            taskLabel: taskLabel,
            speaker: .operator(displayName: nil),
            templateKey: MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: phase, passed: passed),
            templateParams: MissionRunReserveSwapPhaseLogTemplateKey.templateParams(
                phase: phase,
                correlation: correlation,
                detail: detail,
                recipeRaw: recipeRaw
            )
        )
    }

    /// Wingman vacancy: template **.reserve** rows tied to this wingman's primary first, then **auto** reserves (``leaderRosterDeviceId == nil``), then reserves tied to another primary. Within each band: ``slotName`` then ``id``. Other vacancies: ``slotName`` then ``id``.
    private func sortFixedReserveAssignmentsForReserveSwapEnumerate(
        _ rosterRows: inout [MissionRunAssignment],
        vacancy: MissionRunAssignment,
        rosterByID: [UUID: RosterDevice],
        taskID: UUID,
        mission: Mission?
    ) {
        func sortSlotNameThenId(_ lhs: MissionRunAssignment, _ rhs: MissionRunAssignment) -> Bool {
            if lhs.slotName != rhs.slotName { return lhs.slotName < rhs.slotName }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let mission,
              let vacancyDevice = rosterByID[vacancy.rosterDeviceId],
              vacancyDevice.slot == .wingman,
              let primaryForWingman = resolvedLeaderRosterDeviceIdForWingman(vacancyDevice: vacancyDevice, taskID: taskID, mission: mission),
              rosterByID[primaryForWingman]?.slot == .primary
        else {
            rosterRows.sort(by: sortSlotNameThenId)
            return
        }

        func reserveLeaderTier(_ assignment: MissionRunAssignment) -> Int {
            guard let rd = rosterByID[assignment.rosterDeviceId], rd.slot == .reserve else { return 3 }
            if let leader = rd.leaderRosterDeviceId {
                if leader == primaryForWingman { return 0 }
                return 2
            }
            return 1
        }
        rosterRows.sort { a, b in
            let ta = reserveLeaderTier(a), tb = reserveLeaderTier(b)
            if ta != tb { return ta < tb }
            return sortSlotNameThenId(a, b)
        }
    }

    /// Explicit ``RosterDevice/leaderRosterDeviceId`` on the wingman row, or the sole task primary when unambiguous.
    private func resolvedLeaderRosterDeviceIdForWingman(vacancyDevice: RosterDevice, taskID: UUID, mission: Mission) -> UUID? {
        if let explicit = vacancyDevice.leaderRosterDeviceId { return explicit }
        return singlePrimaryRosterDeviceIdOnTaskIfUnambiguous(taskID: taskID, mission: mission)
    }

    private func singlePrimaryRosterDeviceIdOnTaskIfUnambiguous(taskID: UUID, mission: Mission) -> UUID? {
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }) else { return nil }
        let primaries: [UUID] = task.rosterDeviceIds.compactMap { rid in
            guard let d = mission.rosterDevices.first(where: { $0.id == rid }), d.slot == .primary else { return nil }
            return rid
        }
        guard primaries.count == 1, let only = primaries.first else { return nil }
        return only
    }

    /// Marks a **vehicle** (fleet storage key) as unusable for reserve-pool draws until cleared.
    func markFleetVehicleWrittenOffForReservePool(storageKey: String) {
        let key = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var next = writtenOffFleetVehicleStorageKeysForReservePool
        next.insert(key)
        writtenOffFleetVehicleStorageKeysForReservePool = next
    }

    /// Clears run-level reserve-pool written-off for a fleet storage key (e.g. after mistaken mark).
    func clearFleetVehicleWrittenOffForReservePool(storageKey: String) {
        let key = storageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        var next = writtenOffFleetVehicleStorageKeysForReservePool
        next.remove(key)
        writtenOffFleetVehicleStorageKeysForReservePool = next
    }

    func isFleetVehicleWrittenOffForReservePool(storageKey: String) -> Bool {
        writtenOffFleetVehicleStorageKeysForReservePool.contains(storageKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Copies a squad ``MissionRunAssignment`` binding into the task’s floating reserve **pool** when policy allows.
    ///
    /// **Legacy** text-only assignments skip fleet hub checks. **Fleet** assignments require ``FleetLinkService`` and ``SitlService``,
    /// a resolved stream id, ``VehicleLifecycleStage/live``, and non-critical battery band (see ``FleetVehicleOperationalModel/BatterySummary/trafficBand``).
    /// If the pool already holds a slot with the same ``attachedFleetVehicleToken``, that row is **updated** instead of appending.
    @discardableResult
    func returnAssignmentToReservePool(
        _ assignment: MissionRunAssignment,
        forTaskID taskID: UUID
    ) -> MissionRunReservePoolReturnAssignmentOutcome {
        guard assignment.hasFleetOrLegacyAssignment else { return .rejectedNoBinding }
        let payload = reservePoolReturnPayload(from: assignment, forTaskID: taskID)
        guard let fleetKey = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fleetKey.isEmpty
        else {
            return commitReservePoolSlotFromAssignment(payload, mergeFleetStorageKey: nil, taskID: taskID)
        }
        if isFleetVehicleWrittenOffForReservePool(storageKey: fleetKey) {
            return .rejectedFleetVehicleWrittenOff(storageKey: fleetKey)
        }
        guard let fleetLink, let sitl else { return .rejectedFleetContextUnavailable }
        guard let token = FleetMissionVehicleToken(storageKey: fleetKey) else { return .rejectedFleetVehicleUnresolved }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            return .rejectedFleetVehicleUnresolved
        }
        let operational = operationalTelemetrySummaryForReservePool(vehicleID: vehicleID, fleetLink: fleetLink)
        if let rejection = operational.reservePoolReturnFromAssignmentRejection() {
            return rejection
        }
        return commitReservePoolSlotFromAssignment(payload, mergeFleetStorageKey: fleetKey, taskID: taskID)
    }

    /// Moves an eligible floating reserve **pool** binding onto the roster slot ``assignmentID`` for ``taskID``,
    /// and moves the roster slot’s prior binding onto **the same** pool berth (no new pool rows).
    ///
    /// Candidate pool rows match ``enumerateReserveSwapCandidates`` / ``availableReservePoolEntries(forTaskID:classCompatibleWithAssignmentId:)``;
    /// selection uses ``MissionRunReserveSwapRankingPolicy`` (default **uniform random** among class-compatible pool rows that are not the same fleet token as the vacancy). Fixed template **reserve** rows are enumerated for pickers and committed via ``swapRosterVacancyWithFixedTemplateReserveAssignment``.
    /// Emits ``MissionRunLogTemplateKey/floatingReserveSwapEngaged`` on success.
    @discardableResult
    func swapRosterAssignmentWithRandomFloatingReserve(
        assignmentID: UUID,
        taskID: UUID,
        triggerSource: String = "operator.missionControlSetup",
        rankingPolicy: MissionRunReserveSwapRankingPolicy = .uniformRandom
    ) -> MissionRunFloatingReserveSwapOutcome {
        guard MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: sessionPhase) else {
            return .blockedBySessionPhase
        }
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else {
            return .assignmentNotFound
        }
        guard assignmentsBoundToMissionTask(taskID: taskID).contains(where: { $0.id == assignmentID }) else {
            return .assignmentNotBoundToTask
        }

        let current = assignments[idx]
        let baseEligible = availableReservePoolEntries(
            forTaskID: taskID,
            classCompatibleWithAssignmentId: assignmentID
        )
        let baseEligibleIgnoringClass = availableReservePoolEntries(forTaskID: taskID, classCompatibleWithAssignmentId: nil)
        let enumerated = enumerateReserveSwapCandidates(vacancyAssignmentID: assignmentID, taskID: taskID)
        var poolCandidates: [MissionRunReserveSwapCandidate] = enumerated.filter {
            if case .floatingPool(let tid, _) = $0 { return tid == taskID }
            return false
        }
        let vacancyToken = Self.normalizedFleetStorageKey(current.attachedFleetVehicleToken)
        if !vacancyToken.isEmpty {
            poolCandidates = poolCandidates.filter {
                guard case .floatingPool(_, let slot) = $0 else { return false }
                return Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken) != vacancyToken
            }
        }
        guard let picked = rankingPolicy.pick(from: poolCandidates),
              case .floatingPool(_, let pickSnap) = picked
        else {
            if baseEligibleIgnoringClass.isEmpty { return .noEligiblePoolSlots }
            if baseEligible.isEmpty { return .noClassCompatiblePoolSlots }
            return .identicalFleetBindingNoOp
        }

        guard floatingReserveSwapPreCommitDedupeAndOperationalHold(
            pick: pickSnap,
            vacancyAssignmentID: assignmentID,
            taskID: taskID
        ) else {
            return .pickRejectedDuplicateOrStaleBinding
        }

        return commitFloatingReservePoolPickToVacancy(
            pickSnap: pickSnap,
            vacancyAssignmentIndex: idx,
            taskID: taskID,
            triggerSource: triggerSource
        )
    }

    /// Same roster / pool commit as ``swapRosterAssignmentWithRandomFloatingReserve`` but with an operator-chosen **pool berth** (MC-R picker).
    ///
    /// **Return path (displaced binding):** the prior vacancy binding is written onto **this same berth id** after commit
    /// (``MissionRunReserveSwapReplacedActiveReturnPathPolicy/floatingPoolSwapInWritesPriorBindingToConsumedBerth``) — not
    /// ``returnAssignmentToReservePool``.
    ///
    /// ``poolSlotID`` must appear as a ``MissionRunReserveSwapCandidate/floatingPool`` row in ``enumerateReserveSwapCandidates`` for the vacancy.
    @discardableResult
    func swapRosterAssignmentWithFloatingReservePoolSlot(
        assignmentID: UUID,
        taskID: UUID,
        poolSlotID: UUID,
        triggerSource: String = "operator.missionControlRunning.reserveSwap"
    ) -> MissionRunFloatingReserveSwapOutcome {
        guard MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: sessionPhase) else {
            return .blockedBySessionPhase
        }
        guard let idx = assignments.firstIndex(where: { $0.id == assignmentID }) else {
            return .assignmentNotFound
        }
        guard assignmentsBoundToMissionTask(taskID: taskID).contains(where: { $0.id == assignmentID }) else {
            return .assignmentNotBoundToTask
        }

        let enumerated = enumerateReserveSwapCandidates(vacancyAssignmentID: assignmentID, taskID: taskID)
        let poolCandidates: [MissionRunReserveSwapCandidate] = enumerated.compactMap { c in
            guard case .floatingPool(let tid, let slot) = c, tid == taskID else { return nil }
            return .floatingPool(taskID: tid, slot: slot)
        }
        guard poolCandidates.contains(where: {
            if case .floatingPool(_, let slot) = $0 { return slot.id == poolSlotID }
            return false
        }) else {
            return .poolSlotNotEligible
        }
        guard let pickSnap = reservePool(forTaskID: taskID).entries.first(where: { $0.id == poolSlotID })
        else {
            return .poolSlotNotEligible
        }

        guard floatingReserveSwapPreCommitDedupeAndOperationalHold(
            pick: pickSnap,
            vacancyAssignmentID: assignmentID,
            taskID: taskID
        ) else {
            return .pickRejectedDuplicateOrStaleBinding
        }

        return commitFloatingReservePoolPickToVacancy(
            pickSnap: pickSnap,
            vacancyAssignmentIndex: idx,
            taskID: taskID,
            triggerSource: triggerSource
        )
    }

    /// Swaps ``attachedFleetVehicleToken`` / ``attachedDevice`` between a **primary or wingman** vacancy and a **template `.reserve`**
    /// roster assignment on the same task (engagement-consent path, MC-R operator prompt, or autonomous engagement).
    ///
    /// **Return path (displaced binding):** pairwise exchange — the prior vacancy binding ends on the **reserve** assignment row
    /// (``MissionRunReserveSwapReplacedActiveReturnPathPolicy/fixedReserveSwapInIsPairwiseRosterBindingExchange``); the pool
    /// is untouched.
    ///
    /// ``reserveAssignmentID`` must appear as ``MissionRunReserveSwapCandidate/fixedRosterReserve`` in
    /// ``enumerateReserveSwapCandidates(vacancyAssignmentID:taskID:ordering:)`` (any ordering) at commit time. Emits ``MissionRunLogTemplateKey/fixedRosterReserveSwapEngaged`` on success.
    @discardableResult
    func swapRosterVacancyWithFixedTemplateReserveAssignment(
        vacancyAssignmentID: UUID,
        reserveAssignmentID: UUID,
        taskID: UUID,
        triggerSource: String = "missionControl.reserve.fixedRosterSwap"
    ) -> MissionRunFixedRosterReserveSwapOutcome {
        guard MissionRunReserveSwapSessionPhasePolicy.allowsReserveSwapMutation(sessionPhase: sessionPhase) else {
            return .blockedBySessionPhase
        }
        guard let vIdx = assignments.firstIndex(where: { $0.id == vacancyAssignmentID }) else {
            return .assignmentNotFound
        }
        guard let rIdx = assignments.firstIndex(where: { $0.id == reserveAssignmentID }) else {
            return .assignmentNotFound
        }
        guard vIdx != rIdx else { return .reserveNotEligibleForVacancy }
        guard assignmentsBoundToMissionTask(taskID: taskID).contains(where: { $0.id == vacancyAssignmentID }),
              assignmentsBoundToMissionTask(taskID: taskID).contains(where: { $0.id == reserveAssignmentID })
        else {
            return .assignmentNotBoundToTask
        }

        let enumerated = enumerateReserveSwapCandidates(vacancyAssignmentID: vacancyAssignmentID, taskID: taskID)
        let reserveStillEnumerated = enumerated.contains { cand in
            if case .fixedRosterReserve(let a) = cand { return a.id == reserveAssignmentID }
            return false
        }
        guard reserveStillEnumerated else { return .reserveNotEligibleForVacancy }

        let vac = assignments[vIdx]
        let res = assignments[rIdx]

        let vacTok = Self.normalizedFleetStorageKey(vac.attachedFleetVehicleToken)
        let resTok = Self.normalizedFleetStorageKey(res.attachedFleetVehicleToken)
        if !vacTok.isEmpty, vacTok == resTok { return .identicalFleetBindingNoOp }
        if vacTok.isEmpty, resTok.isEmpty {
            let vd = vac.attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines)
            let rd = res.attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !vd.isEmpty, vd == rd { return .identicalFleetBindingNoOp }
        }

        guard fixedRosterReserveSwapPreCommitDedupeAndOperationalHold(vacancy: vac, reserve: res) else {
            return .pickRejectedDuplicateOrStaleBinding
        }

        var next = assignments
        let tVac = next[vIdx].attachedFleetVehicleToken
        let dVac = next[vIdx].attachedDevice
        next[vIdx].attachedFleetVehicleToken = next[rIdx].attachedFleetVehicleToken
        next[vIdx].attachedDevice = next[rIdx].attachedDevice
        next[rIdx].attachedFleetVehicleToken = tVac
        next[rIdx].attachedDevice = dVac
        nilOutSlotLifecycleLanesOnRosterRowsAfterReserveBindingChange(
            assignmentIDs: [vacancyAssignmentID, reserveAssignmentID],
            mutatedRows: &next
        )
        assignments = next
        clearOperatorLaunchPoses(forAssignmentIDs: [vac.id, res.id])
        clearRosterSimStartPoseSnapshots(forAssignmentIDs: [vac.id, res.id])

        let taskLabel = template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
        systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: taskLabel,
            speaker: .operator(displayName: nil),
            templateKey: MissionRunLogTemplateKey.fixedRosterReserveSwapEngaged,
            templateParams: [
                "vacancySlotID": vacancyAssignmentID.uuidString,
                "vacancySlot": vac.slotName,
                "reserveSlotID": reserveAssignmentID.uuidString,
                "reserveSlot": res.slotName,
                "source": triggerSource,
            ]
        )

        let fixedReserveVehicleIDForLog: String = {
            guard let fl = fleetLink, let st = sitl,
                  let raw = res.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let tok = FleetMissionVehicleToken(storageKey: raw),
                  let vid = resolvedFleetStreamVehicleID(token: tok, fleetLink: fl, sitl: st)
            else { return "-" }
            return vid
        }()
        let fixedSwapCorrelation = MissionRunReserveRecipeRunnerCorrelation.fixedRosterReserve(
            missionRunID: id,
            missionTaskID: taskID,
            vacancyAssignmentID: vacancyAssignmentID,
            reserveAssignment: res,
            vehicleID: fixedReserveVehicleIDForLog
        )
        appendReserveSwapPipelinePhaseLog(
            phase: .rosterCommit,
            passed: true,
            correlation: fixedSwapCorrelation,
            detail: "Fixed reserve roster commit completed."
        )

        refreshDerivedTaskStates()
        return .success
    }

    /// §5 (``TaskRosterAssignmentStatesToDo.md`` — reserve draw / return): roster swap commits change which vehicle occupies stable ``MissionRunAssignment`` rows. Clear persisted ``slotLifecycleLanes`` so §3 / §4 policy evidence is not attributed to the wrong stream after a token change; effective lanes read **idle** until writers repopulate.
    ///
    /// **Not** ``supersededReassigned`` as a lingering post-swap state: that value is merge-terminal on the commanded lane and blocks §4 dispatch-start transitions until cleared.
    private func nilOutSlotLifecycleLanesOnRosterRowsAfterReserveBindingChange(
        assignmentIDs: [UUID],
        mutatedRows: inout [MissionRunAssignment]
    ) {
        guard !assignmentIDs.isEmpty else { return }
        let touch = Set(assignmentIDs)
        for i in mutatedRows.indices where touch.contains(mutatedRows[i].id) {
            mutatedRows[i].slotLifecycleLanes = nil
        }
    }

    private func commitFloatingReservePoolPickToVacancy(
        pickSnap: MissionRunReservePoolSlot,
        vacancyAssignmentIndex idx: Int,
        taskID: UUID,
        triggerSource: String
    ) -> MissionRunFloatingReserveSwapOutcome {
        let assignmentID = assignments[idx].id
        let oldAssignment = assignments[idx]
        let poolSlotID = pickSnap.id

        if oldAssignment.hasFleetOrLegacyAssignment,
           let reject = floatingReservePriorBindingRejectedIfReturnedToPoolBerth(oldAssignment)
        {
            return .returnRejected(reject)
        }

        let newPoolSlot = MissionRunReservePoolSlot(
            id: poolSlotID,
            label: pickSnap.label,
            attachedFleetVehicleToken: oldAssignment.hasFleetOrLegacyAssignment
                ? oldAssignment.attachedFleetVehicleToken
                : nil,
            attachedDevice: oldAssignment.hasFleetOrLegacyAssignment ? oldAssignment.attachedDevice : ""
        )
        var nextPool = reservePool(forTaskID: taskID)
        guard let pIdx = nextPool.entries.firstIndex(where: { $0.id == poolSlotID }) else {
            return .poolClearFailed
        }
        nextPool.entries[pIdx] = newPoolSlot

        var nextAssignments = assignments
        nextAssignments[idx].attachedFleetVehicleToken = pickSnap.attachedFleetVehicleToken
        nextAssignments[idx].attachedDevice = pickSnap.attachedDevice
        nilOutSlotLifecycleLanesOnRosterRowsAfterReserveBindingChange(assignmentIDs: [assignmentID], mutatedRows: &nextAssignments)

        assignments = nextAssignments
        clearOperatorLaunchPoses(forAssignmentIDs: [assignmentID])
        clearRosterSimStartPoseSnapshots(forAssignmentIDs: [assignmentID])
        clearReservePoolSimStartPoseSnapshots(forSlotIDs: [poolSlotID])
        var nextReservePools = reservePoolByTaskID
        nextReservePools[taskID] = nextPool
        reservePoolByTaskID = nextReservePools

        let taskLabel = template?.routeMacro.tasks.first(where: { $0.id == taskID })?.name
        systems.logging.appendLogEvent(
            level: .info,
            taskID: taskID,
            taskLabel: taskLabel,
            speaker: .operator(displayName: nil),
            templateKey: MissionRunLogTemplateKey.floatingReserveSwapEngaged,
            templateParams: [
                "slot": oldAssignment.slotName,
                "slotID": assignmentID.uuidString,
                "poolSlotID": poolSlotID.uuidString,
                "source": triggerSource,
            ]
        )

        let reserveVehicleIDForLog: String = {
            guard let fl = fleetLink, let st = sitl,
                  let raw = pickSnap.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty,
                  let tok = FleetMissionVehicleToken(storageKey: raw),
                  let vid = resolvedFleetStreamVehicleID(token: tok, fleetLink: fl, sitl: st)
            else { return "-" }
            return vid
        }()
        let poolSwapCorrelation = MissionRunReserveRecipeRunnerCorrelation.floatingPoolReserve(
            missionRunID: id,
            missionTaskID: taskID,
            vacancyAssignmentID: assignmentID,
            poolSlot: pickSnap,
            vehicleID: reserveVehicleIDForLog
        )
        appendReserveSwapPipelinePhaseLog(
            phase: .rosterCommit,
            passed: true,
            correlation: poolSwapCorrelation,
            detail: "Floating pool roster commit completed."
        )

        refreshDerivedTaskStates()
        return .success(usedPoolSlotID: poolSlotID, returnedPriorBindingToPool: nil)
    }

    /// Same eligibility gates as ``returnAssignmentToReservePool`` for this binding, without mutating the pool (used before an in-place roster ↔ pool berth swap).
    private func floatingReservePriorBindingRejectedIfReturnedToPoolBerth(
        _ assignment: MissionRunAssignment
    ) -> MissionRunReservePoolReturnAssignmentOutcome? {
        guard assignment.hasFleetOrLegacyAssignment else { return nil }
        guard let fleetKey = assignment.attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fleetKey.isEmpty
        else {
            return nil
        }
        if isFleetVehicleWrittenOffForReservePool(storageKey: fleetKey) {
            return .rejectedFleetVehicleWrittenOff(storageKey: fleetKey)
        }
        guard let fleetLink, let sitl else { return .rejectedFleetContextUnavailable }
        guard let token = FleetMissionVehicleToken(storageKey: fleetKey) else { return .rejectedFleetVehicleUnresolved }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            return .rejectedFleetVehicleUnresolved
        }
        let operational = operationalTelemetrySummaryForReservePool(vehicleID: vehicleID, fleetLink: fleetLink)
        return operational.reservePoolReturnFromAssignmentRejection()
    }

    /// Payload for ``returnAssignmentToReservePool`` — **never** reuse the roster row’s ``MissionRunAssignment/slotName`` as the pool berth label (pool rows are not roster slots).
    private func reservePoolReturnPayload(from assignment: MissionRunAssignment, forTaskID taskID: UUID) -> MissionRunReservePoolSlot {
        let ord = reservePool(forTaskID: taskID).entries.count + 1
        return MissionRunReservePoolSlot(
            label: "Reserve \(ord)",
            attachedFleetVehicleToken: assignment.attachedFleetVehicleToken,
            attachedDevice: assignment.attachedDevice
        )
    }

    private func operationalTelemetrySummaryForReservePool(
        vehicleID: String,
        fleetLink: FleetLinkService
    ) -> FleetVehicleOperationalModel {
        if let model = fleetLink.vehicleModel(forVehicleID: vehicleID) {
            return model.collections.operational
        }
        let lifecycle = fleetLink.vehicleStatus(forVehicleID: vehicleID) ?? VehicleLifecycleStatus(stage: .awaitingTelemetry)
        let hub = fleetLink.hubTelemetryByVehicleID[vehicleID]
        return FleetVehicleOperationalModel(hub: hub, lifecycleStatus: lifecycle)
    }

    private func commitReservePoolSlotFromAssignment(
        _ payload: MissionRunReservePoolSlot,
        mergeFleetStorageKey: String?,
        taskID: UUID
    ) -> MissionRunReservePoolReturnAssignmentOutcome {
        var pool = reservePool(forTaskID: taskID)
        let outcome = pool.applyReservePoolReturnPayload(payload, mergeFleetStorageKey: mergeFleetStorageKey)
        var next = reservePoolByTaskID
        next[taskID] = pool
        reservePoolByTaskID = next
        return outcome
    }

    private func passesReservePoolSlotOperationalDrawGate(_ slot: MissionRunReservePoolSlot) -> Bool {
        let key = Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken)
        guard !key.isEmpty else { return true }
        return missionRunFleetBindingPassesReservePoolOperationalDrawGate(fleetStorageKey: key)
    }

    /// Hub lifecycle + battery gate for reserve **pool draw / swap pick** (``FleetVehicleOperationalModel/qualifiesForMissionRunReservePoolOperationalDraw``).
    /// **Does not** read roster ``MissionRunAssignment/slotLifecycleLanes`` — merged ``policyFailed`` / ``blockedNoVehicle`` on a squad row must not hide otherwise-eligible pool berths.
    private func missionRunFleetBindingPassesReservePoolOperationalDrawGate(fleetStorageKey: String) -> Bool {
        let key = fleetStorageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return true }
        guard let fleetLink, let sitl else { return true }
        guard let token = FleetMissionVehicleToken(storageKey: key) else { return false }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            return false
        }
        let operational = operationalTelemetrySummaryForReservePool(vehicleID: vehicleID, fleetLink: fleetLink)
        return operational.qualifiesForMissionRunReservePoolOperationalDraw
    }

    private static func normalizedFleetStorageKey(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isReservePoolSlotEligibleForRandomPick(_ slot: MissionRunReservePoolSlot) -> Bool {
        guard slot.hasFleetOrLegacyBinding else { return false }
        if let tok = slot.attachedFleetVehicleToken, !tok.isEmpty {
            return !writtenOffFleetVehicleStorageKeysForReservePool.contains(tok)
        }
        return true
    }

    /// Expected granular class from the mission template row for this assignment’s ``MissionRunAssignment/rosterDeviceId``.
    func expectedFleetVehicleClassForRosterAssignment(_ assignment: MissionRunAssignment) -> FleetVehicleType {
        template?.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })?.vehicleClass ?? .unknown
    }

    private func candidateFleetVehicleTypeForReservePoolSlot(_ slot: MissionRunReservePoolSlot) -> FleetVehicleType? {
        candidateFleetVehicleTypeForAttachedFleetToken(slot.attachedFleetVehicleToken)
    }

    private func candidateFleetVehicleTypeForAttachedFleetToken(_ storageKey: String?) -> FleetVehicleType? {
        let key = Self.normalizedFleetStorageKey(storageKey)
        guard !key.isEmpty,
              let fleetLink, let sitl,
              let token = FleetMissionVehicleToken(storageKey: key),
              let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
        else { return nil }
        return fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.vehicleType
    }

    private func rosterReserveFleetBindingMatchesVacancyClass(expected: FleetVehicleType, assignment: MissionRunAssignment) -> Bool {
        if expected == .unknown { return true }
        guard let candidate = candidateFleetVehicleTypeForAttachedFleetToken(assignment.attachedFleetVehicleToken) else {
            return false
        }
        return FleetVehicleType.substitutionMatches(
            required: expected,
            candidate: candidate,
            policy: .missionRunReserveSwap
        )
    }

    private func reservePoolSlotMatchesVacancyClass(expected: FleetVehicleType, slot: MissionRunReservePoolSlot) -> Bool {
        if expected == .unknown { return true }
        guard let candidate = candidateFleetVehicleTypeForReservePoolSlot(slot) else { return false }
        return FleetVehicleType.substitutionMatches(
            required: expected,
            candidate: candidate,
            policy: .missionRunReserveSwap
        )
    }

    /// Last-moment validation before mutating roster/pool on a floating reserve swap (telemetry drift + duplicate fleet token).
    private func floatingReserveSwapPreCommitDedupeAndOperationalHold(
        pick: MissionRunReservePoolSlot,
        vacancyAssignmentID: UUID,
        taskID: UUID
    ) -> Bool {
        let key = Self.normalizedFleetStorageKey(pick.attachedFleetVehicleToken)
        if !key.isEmpty {
            if isFleetVehicleWrittenOffForReservePool(storageKey: key) { return false }
            if fleetStorageKeyBoundOnAnotherRosterAssignment(excludingAssignmentID: vacancyAssignmentID, fleetStorageKey: key) {
                return false
            }
            if fleetTokenHeldInAdditionalReservePoolBerth(fleetStorageKey: key, pickTaskID: taskID, pickSlotID: pick.id) {
                return false
            }
        }
        return passesReservePoolSlotOperationalDrawGate(pick)
    }

    /// Last-moment validation before mutating two roster rows on a fixed-reserve ↔ vacancy swap.
    ///
    /// **Operational draw (``FleetVehicleOperationalModel/qualifiesForMissionRunReservePoolOperationalDraw``):** applies to the **incoming** reserve binding (the vehicle moving onto the vacancy). The **outgoing** vacancy stream is **not** gated with the pool-return bar — that bar is for ``returnAssignmentToReservePool`` / floating pool commits; a distressed active may still bench-swap onto template ``.reserve``. Roster **slot** chip evidence (``policyFailed`` / ``blockedNoVehicle`` on ``MissionRunAssignment/slotLifecycleLanes``) is **not** consulted here or in ``availableReservePoolEntries`` — it must not deadlock reserve enumeration or commit.
    private func fixedRosterReserveSwapPreCommitDedupeAndOperationalHold(
        vacancy: MissionRunAssignment,
        reserve: MissionRunAssignment
    ) -> Bool {
        let allowedIDs: Set<UUID> = [vacancy.id, reserve.id]

        let resKey = Self.normalizedFleetStorageKey(reserve.attachedFleetVehicleToken)
        if !resKey.isEmpty {
            if isFleetVehicleWrittenOffForReservePool(storageKey: resKey) { return false }
            if !missionRunFleetBindingPassesReservePoolOperationalDrawGate(fleetStorageKey: resKey) { return false }
            if fleetStorageKeyBoundOutsideAssignmentPair(fleetStorageKey: resKey, allowedAssignmentIDs: allowedIDs) {
                return false
            }
        }

        let vacKey = Self.normalizedFleetStorageKey(vacancy.attachedFleetVehicleToken)
        if !vacKey.isEmpty {
            if isFleetVehicleWrittenOffForReservePool(storageKey: vacKey) { return false }
            if fleetStorageKeyBoundOutsideAssignmentPair(fleetStorageKey: vacKey, allowedAssignmentIDs: allowedIDs) {
                return false
            }
        }

        return true
    }

    /// `true` when the fleet key appears on another roster row **or** any floating pool berth, excluding the two swap participants.
    private func fleetStorageKeyBoundOutsideAssignmentPair(fleetStorageKey: String, allowedAssignmentIDs: Set<UUID>) -> Bool {
        let k = Self.normalizedFleetStorageKey(fleetStorageKey)
        guard !k.isEmpty else { return false }
        for a in assignments where !allowedAssignmentIDs.contains(a.id) {
            if Self.normalizedFleetStorageKey(a.attachedFleetVehicleToken) == k { return true }
        }
        for (_, pool) in reservePoolByTaskID {
            for slot in pool.entries where Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken) == k {
                return true
            }
        }
        return false
    }

    private func fleetStorageKeyBoundOnAnotherRosterAssignment(excludingAssignmentID: UUID, fleetStorageKey: String) -> Bool {
        let k = Self.normalizedFleetStorageKey(fleetStorageKey)
        guard !k.isEmpty else { return false }
        return assignments.contains { a in
            a.id != excludingAssignmentID && Self.normalizedFleetStorageKey(a.attachedFleetVehicleToken) == k
        }
    }

    /// `true` when the same non-empty fleet storage key appears on another pool berth (any task) besides ``pickSlotID`` on ``pickTaskID``.
    private func fleetTokenHeldInAdditionalReservePoolBerth(
        fleetStorageKey: String,
        pickTaskID: UUID,
        pickSlotID: UUID
    ) -> Bool {
        let k = Self.normalizedFleetStorageKey(fleetStorageKey)
        guard !k.isEmpty else { return false }
        for (tid, pool) in reservePoolByTaskID {
            for slot in pool.entries {
                if tid == pickTaskID && slot.id == pickSlotID { continue }
                if Self.normalizedFleetStorageKey(slot.attachedFleetVehicleToken) == k {
                    return true
                }
            }
        }
        return false
    }

    private func pruneReservePoolsToMatchTasks(in mission: Mission) {
        let valid = Set(mission.routeMacro.tasks.map(\.id))
        reservePoolByTaskID = reservePoolByTaskID.filter { valid.contains($0.key) }
        reservePoolBulkSimHomeByTaskID = reservePoolBulkSimHomeByTaskID.filter { valid.contains($0.key) }
    }

    /// Records the last **bulk** pool map home coordinate for ``taskID`` (MCS setup).
    func setReservePoolBulkSimHome(_ coordinate: RouteCoordinate, forTaskID taskID: UUID) {
        var next = reservePoolBulkSimHomeByTaskID
        next[taskID] = coordinate
        reservePoolBulkSimHomeByTaskID = next
    }

    /// Last bulk pool map home coordinate for ``taskID``, if any.
    func reservePoolBulkSimHome(forTaskID taskID: UUID) -> RouteCoordinate? {
        reservePoolBulkSimHomeByTaskID[taskID]
    }

    private enum RuntimeMissionPointsSyncReason {
        case initial
        case templateRefresh
    }

    /// Copies ``Mission/missionPoints`` into ``runtimeMissionPoints`` while still in **setup**, or when the
    /// mission identity changes; preserves live edits after the run has started.
    private func syncRuntimeMissionPointsFromTemplate(_ mission: Mission, reason: RuntimeMissionPointsSyncReason) {
        let shouldReplaceFromTemplate: Bool = {
            if mission.id != missionId { return true }
            if status == .setup { return true }
            return false
        }()
        guard shouldReplaceFromTemplate else { return }
        let previousCount = runtimeMissionPoints.count
        runtimeMissionPoints = mission.missionPoints
        let newCount = runtimeMissionPoints.count
        if newCount > 0 || previousCount != newCount {
            logRuntimeMissionPointsSeeded(count: newCount, reason: reason)
        }
    }

    private func logRuntimeMissionPointsSeeded(count: Int, reason: RuntimeMissionPointsSyncReason) {
        let reasonLabel = reason == .initial ? "init" : "template"
        systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionPointRuntimeSeeded,
            templateParams: [
                "count": "\(count)",
                "reason": reasonLabel,
            ]
        )
    }

    /// Appends a run-only point. Fails if ``pointId`` duplicates an existing runtime row (empty ids get a unique temp slug first). Does **not** mutate ``Mission`` on disk.
    ///
    /// New rows receive the next numeric `rally.n` / `extraction.n` slug (same parsing rules as ``MissionPoint/slugOrdinalSuffix``) so ``MissionPoint/mapChipLabel`` matches the Missions editor without rewriting template-seeded slugs elsewhere in the list.
    @discardableResult
    func applyRuntimeMissionPointCreate(_ point: MissionPoint, source: String = "operator") -> Bool {
        var p = point
        if p.pointId.isEmpty {
            p.pointId = "mre.create.\(p.id.uuidString.lowercased())"
        }
        guard !runtimeMissionPoints.contains(where: { $0.pointId == p.pointId }) else { return false }
        p.catchmentRadiusM = MissionPoint.clampedCatchmentRadiusM(p.catchmentRadiusM)
        let rowID = p.id
        runtimeMissionPoints.append(p)
        guard let idx = runtimeMissionPoints.firstIndex(where: { $0.id == rowID }) else { return false }
        let others = runtimeMissionPoints.enumerated().filter { $0.offset != idx }.map(\.element)
        runtimeMissionPoints[idx].pointId = Self.nextRuntimeMissionPointSlug(kind: runtimeMissionPoints[idx].kind, among: others)
        let created = runtimeMissionPoints[idx]
        systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionPointRuntimeCreated,
            templateParams: [
                "pointId": created.pointId,
                "kind": created.kind.rawValue,
                "source": source,
                "lat": "\(created.coordinate.lat)",
                "lon": "\(created.coordinate.lon)",
            ]
        )
        return true
    }

    /// Mutates one runtime point by row ``MissionPoint/id``. Re-clamps ``catchmentRadiusM`` after mutation.
    @discardableResult
    func applyRuntimeMissionPointUpdate(id: UUID, source: String = "operator", mutate: (inout MissionPoint) -> Void) -> Bool {
        guard let idx = runtimeMissionPoints.firstIndex(where: { $0.id == id }) else { return false }
        var p = runtimeMissionPoints[idx]
        let oldKind = p.kind
        mutate(&p)
        p.catchmentRadiusM = MissionPoint.clampedCatchmentRadiusM(p.catchmentRadiusM)
        if p.kind != oldKind {
            let others = runtimeMissionPoints.enumerated().filter { $0.offset != idx }.map(\.element)
            p.pointId = Self.nextRuntimeMissionPointSlug(kind: p.kind, among: others)
        }
        runtimeMissionPoints[idx] = p
        let logged = runtimeMissionPoints[idx]
        systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionPointRuntimeUpdated,
            templateParams: [
                "pointId": logged.pointId,
                "source": source,
            ]
        )
        return true
    }

    /// Next `rally.n` / `extraction.n` with integer **n** strictly greater than any existing same-kind slug in `among` whose `pointId` is already `kind` + dot + digits (template / MCR rows). Non-numeric tails (e.g. `rally.alpha`) are ignored for the max so they do not consume ordinals.
    private static func nextRuntimeMissionPointSlug(kind: MissionPointKind, among points: [MissionPoint]) -> String {
        MissionPoint.makeUniquePointId(kind: kind, existing: Set(points.map(\.pointId)))
    }

    /// Sets ``MissionPoint/isClosed`` for soft retirement / reopen. Does **not** delete the row (MRE cannot delete points).
    @discardableResult
    func applyRuntimeMissionPointSetClosed(id: UUID, isClosed: Bool, source: String = "operator") -> Bool {
        guard let idx = runtimeMissionPoints.firstIndex(where: { $0.id == id }) else { return false }
        var p = runtimeMissionPoints[idx]
        guard p.isClosed != isClosed else { return true }
        p.isClosed = isClosed
        runtimeMissionPoints[idx] = p
        systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.missionPointRuntimeClosedChanged,
            templateParams: [
                "pointId": p.pointId,
                "closed": isClosed ? "true" : "false",
                "source": source,
            ]
        )
        return true
    }

    internal func mutateCompiledPlan(_ plan: MissionControlPlan?) {
        compiledPlan = plan
    }

    internal func setSessionPhase(_ phase: MissionRunSessionPhase) {
        sessionPhase = phase
        refreshDerivedTaskStates()
    }

    internal func clearEvents() {
        events.removeAll()
    }

    internal func clearFinishedMissionCycleVehicleIDs() {
        finishedMissionCycleVehicleIDsByTaskID.removeAll()
    }

    internal func clearFinishedMissionCycleVehicleIDs(forTaskID taskID: UUID) {
        finishedMissionCycleVehicleIDsByTaskID.removeValue(forKey: taskID)
    }

    internal func markFinishedMissionCycleVehicleID(_ vehicleID: String, forTaskID taskID: UUID) {
        var next = finishedMissionCycleVehicleIDsByTaskID
        var bucket = next[taskID] ?? []
        bucket.insert(vehicleID)
        next[taskID] = bucket
        finishedMissionCycleVehicleIDsByTaskID = next
    }

    /// Clears in-flight cycle tracking only — preserves squad policy issued markers and derived squad states (run end-mode entry).
    internal func clearActiveCycleInFlightTracking() {
        activeCycleTaskIDs.removeAll()
        activeCycleSquadAssignmentIDs = []
        finishedMissionCycleVehicleIDsBySquadAssignmentID = [:]
        refreshDerivedTaskStates()
    }

    internal func clearActiveCycleTasks() {
        activeCycleTaskIDs.removeAll()
        clearSquadCycleTracking()
        refreshDerivedTaskStates()
    }

    internal func removeTaskFromActiveCycle(_ taskID: UUID) {
        let squads = primarySquads(forTaskID: taskID)
        var removed = false
        for squad in squads {
            if activeCycleSquadAssignmentIDs.remove(squad.assignment.id) != nil {
                removed = true
            }
        }
        guard removed else { return }
        syncActiveCycleTaskIDsFromSquads()
        refreshDerivedTaskStates()
    }

    internal func markTaskActiveInCurrentCycle(_ taskID: UUID) {
        if let mission = template {
            markFirstWaveSquadsActiveInCurrentCycle(taskID: taskID, mission: mission)
        } else {
            activeCycleTaskIDs.insert(taskID)
        }
        refreshDerivedTaskStates()
    }

    internal func clearTaskCycleCompletionCounts() {
        taskCyclesCompletedByTaskID.removeAll()
        squadCyclesCompletedByAssignmentID = [:]
    }

    internal func clearTaskMissionEndRecoveryAcknowledgements() {
        guard !taskMissionEndRecoveryCompletedByTaskID.isEmpty else { return }
        taskMissionEndRecoveryCompletedByTaskID = []
    }

    internal func clearTaskMissionEndAbortAcknowledgements() {
        guard !taskMissionEndAbortCompletedByTaskID.isEmpty else { return }
        taskMissionEndAbortCompletedByTaskID = []
    }

    /// Call when this task’s roster has finished the orderly recovery protocol (finite cycles finished, or whole-run recovery).
    func acknowledgeTaskMissionEndRecovery(taskID: UUID) {
        operatorMarkMissionTaskTriageState(taskID: taskID, state: .completed)
    }

    func acknowledgeTaskMissionEndAbort(taskID: UUID) {
        operatorMarkMissionTaskTriageState(taskID: taskID, state: .aborted)
    }

    /// True when this task counts toward ``aborting`` → ``aborted`` promotion: abort ack **or** §3 merged-slot rollup while abort wind-down remains **issued** (bound roster rows only).
    private func taskAbortProtocolSatisfiedForAbortingSessionPromotion(taskID: UUID) -> Bool {
        if taskMissionEndAbortCompletedByTaskID.contains(taskID) { return true }
        guard missionTaskAbortWindDownIssuedTaskIDs.contains(taskID) else { return false }
        return MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded(
            assignmentsBoundToMissionTask(taskID: taskID)
        )
    }

    /// When every **enabled** task satisfies ``taskAbortProtocolSatisfiedForAbortingSessionPromotion``, move session from ``MissionRunSessionPhase/aborting`` → ``MissionRunSessionPhase/aborted`` (run stays ``MissionRunStatus/running`` or ``MissionRunStatus/paused`` until the operator marks complete). **Idempotent:** if phase is not ``aborting``, returns without writing; after a successful promotion, repeated calls are no-ops.
    private func promoteSessionPhaseToAbortedIfAllTasksAcknowledgedAbort() {
        guard (status == .running || status == .paused), sessionPhase == .aborting,
              let mission = template
        else { return }
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
        guard enabledTasks.allSatisfy({ taskAbortProtocolSatisfiedForAbortingSessionPromotion(taskID: $0.id) }) else { return }
        setSessionPhase(.aborted)
    }

    internal func recordTaskCycleCompletions(forTaskIDs taskIDs: Set<UUID>) {
        for id in taskIDs {
            taskCyclesCompletedByTaskID[id, default: 0] += 1
        }
        if let mission = template {
            _ = recomputeAggregatedTaskCyclesAndReturnTasksWhoseCycleBoundaryClosed(mission: mission)
        }
        refreshDerivedTaskStates()
    }

    internal func setOneOffDeferredExecution(_ value: MissionOneOffDeferredExecution?) {
        oneOffDeferredExecution = value
    }

    internal func mutateTaskStartDeferral(forTaskID taskID: UUID, value: MissionTaskStartDeferral?) {
        if let value {
            taskStartDeferralByTaskID[taskID] = value
        } else {
            taskStartDeferralByTaskID.removeValue(forKey: taskID)
        }
        refreshDerivedTaskStates()
    }

    internal func clearTaskStartDeferral(forTaskID taskID: UUID? = nil) {
        if let taskID {
            taskStartDeferralByTaskID.removeValue(forKey: taskID)
        } else {
            taskStartDeferralByTaskID.removeAll()
        }
        refreshDerivedTaskStates()
    }

    var includesSimulationVehicles: Bool {
        assignments.contains {
            guard let key = $0.attachedFleetVehicleToken else { return false }
            guard let token = FleetMissionVehicleToken(storageKey: key) else { return false }
            if case .sitl = token { return true }
            return false
        }
    }

    func oneOffScheduledTimeTooFarInPast(referenceNow: Date) -> Bool {
        guard let t = oneOffStartAt else { return false }
        return t.timeIntervalSince(referenceNow) < -Self.oneOffScheduleTimeTolerance
    }

    /// Effective MAVLink mission start deferral for this task (run override or template).
    func startDelayTotalSeconds(forTask taskId: UUID, mission: Mission? = nil) -> TimeInterval {
        if let t = taskStartDelays.first(where: { $0.taskId == taskId }) {
            return t.totalSeconds
        }
        let source = mission ?? template
        if let mission = source,
           let task = mission.routeMacro.tasks.first(where: { $0.id == taskId }) {
            return task.startDelayTotalSeconds
        }
        return 0
    }

    func beginRun() {
        status = .running
        if startedAt == nil {
            startedAt = Date()
        }
        completedAt = nil
        gracefulStopKind = .none
        completionKind = nil
        clearMissionTaskScopedOrchestrationState()
        setSessionPhase(.staging)
    }

    /// Recomputes ``taskStateByTaskID`` from template, run status, session phase, deferrals, and cycle bookkeeping.
    func refreshDerivedTaskStates(now: Date = Date()) {
        pruneRosterSimStartPoseSnapshotsToCurrentAssignments()
        pruneReservePoolSimStartPoseSnapshotsToCurrentSlots()
        refreshDerivedSquadStates(now: now)
        guard let mission = template else {
            if !taskStateByTaskID.isEmpty { taskStateByTaskID = [:] }
            if !taskAttemptingByTaskID.isEmpty { taskAttemptingByTaskID = [:] }
            if !taskMissionEndAttemptByTaskID.isEmpty { taskMissionEndAttemptByTaskID = [:] }
            return
        }
        let previous = taskStateByTaskID
        var next: [UUID: MissionTaskState] = [:]
        next.reserveCapacity(mission.routeMacro.tasks.count)
        for task in mission.routeMacro.tasks {
            next[task.id] = Self.deriveMissionTaskState(task: task, run: self, now: now)
        }
        if next != taskStateByTaskID {
            logMissionControlTaskForceStateTransitionsIfNeeded(previous: previous, next: next, mission: mission)
            taskStateByTaskID = next
        }

        var nextAttempting: [UUID: MissionTaskAttemptState] = [:]
        nextAttempting.reserveCapacity(mission.routeMacro.tasks.count)
        for task in mission.routeMacro.tasks {
            if let attempting = Self.displayedMissionTaskEndAttempt(task: task, run: self) {
                nextAttempting[task.id] = attempting
            }
        }
        if nextAttempting != taskAttemptingByTaskID {
            taskAttemptingByTaskID = nextAttempting
        }

        promoteSessionPhaseToAbortedIfAllTasksAcknowledgedAbort()
    }

    /// Logs when MC’s derived task-force state changes (initial population is silent to avoid noise).
    private func logMissionControlTaskForceStateTransitionsIfNeeded(
        previous: [UUID: MissionTaskState],
        next: [UUID: MissionTaskState],
        mission: Mission
    ) {
        guard !previous.isEmpty else { return }
        let tasksByID = Dictionary(uniqueKeysWithValues: mission.routeMacro.tasks.map { ($0.id, $0) })
        for (taskID, newState) in next {
            guard let oldState = previous[taskID], oldState != newState,
                  let task = tasksByID[taskID]
            else { continue }
            if operatorTriageMarkedMissionTaskStateByTaskID[taskID] == newState,
               newState == .aborted || newState == .completed {
                continue
            }
            systems.logging.appendLogEvent(
                level: .info,
                taskID: task.id,
                taskLabel: task.name,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.taskForceStateChanged,
                templateParams: [
                    "task": task.name,
                    "from": oldState.rawValue,
                    "to": newState.rawValue,
                    "fromDisplay": oldState.displayTitle,
                    "toDisplay": newState.displayTitle,
                ]
            )
        }
    }

    /// Stored mission-end attempt (``taskMissionEndAttemptByTaskID``) unless disabled or operator triage pins a terminal label.
    private static func displayedMissionTaskEndAttempt(task: MissionTask, run: MissionRunEnvironment) -> MissionTaskAttemptState? {
        guard task.enabled else { return nil }
        if let pinned = run.operatorTriageMarkedMissionTaskStateByTaskID[task.id],
           pinned == .aborted || pinned == .completed {
            return nil
        }
        return run.taskMissionEndAttemptByTaskID[task.id]
    }

    /// Same predicate as §3 auto mission-end ack while abort wind-down remains **issued** (no ack-set mutation here).
    private static func slotRollupMirrorsAutoMissionEndAckAbort(task: MissionTask, run: MissionRunEnvironment) -> Bool {
        guard run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id) else { return false }
        return MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsPolicySucceeded(
            run.assignmentsBoundToMissionTask(taskID: task.id)
        )
    }

    /// Same predicate as §3 auto mission-end ack while complete wind-down remains **issued** (no ack-set mutation here).
    private static func slotRollupMirrorsAutoMissionEndAckRecovery(task: MissionTask, run: MissionRunEnvironment) -> Bool {
        let bound = run.assignmentsBoundToMissionTask(taskID: task.id)
        guard MissionRunSlotEvidenceAutoMissionEndAckRules.allBoundRosterRowsSatisfiedForCompleteMissionEndAutoAck(bound) else { return false }
        if run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id) { return true }
        return allPrimariesDispatchedPerSquadCompletePolicyWindDown(task: task, run: run)
    }

    /// Multi-primary finite-cycle: every primary row has dispatched its own complete-policy stack (see ``MissionRunExecutionSubsystem/autoDeliverPerSquadFiniteCycleCompletePolicyIfNeeded``).
    internal static func allPrimariesDispatchedPerSquadCompletePolicyWindDown(task: MissionTask, run: MissionRunEnvironment) -> Bool {
        let primaries = run.primarySquads(forTaskID: task.id)
        guard primaries.count > 1 else { return false }
        let repeats = task.regularity == .continuous || task.regularity == .continuousWithDelay
        guard repeats, task.cycles > 0 else { return false }
        for squad in primaries {
            guard run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(squad.assignment.id) else { return false }
        }
        return true
    }

    private static func deriveMissionTaskState(task: MissionTask, run: MissionRunEnvironment, now: Date) -> MissionTaskState {
        if !task.enabled { return .ready }

        if let pinned = run.operatorTriageMarkedMissionTaskStateByTaskID[task.id],
           pinned == .aborted || pinned == .completed {
            return pinned
        }

        switch run.status {
        case .completed:
            if run.sessionPhase == .aborted {
                let abortDone = run.taskMissionEndAbortCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckAbort(task: task, run: run)
                return abortDone ? .aborted : .aborting
            }
            return .completed
        case .recovery:
            let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
            if recoveryDone { return .completed }
            return .recovery
        case .setup:
            switch run.sessionPhase {
            case .draft, .compiled: return .ready
            case .staging: return .staging
            case .executing, .recovery, .completed, .aborting, .aborted: return .ready
            }
        case .running, .paused:
            break
        }

        let inDeferral = task.enabled
            && (run.status == .running || run.status == .paused)
            && (run.taskStartDeferralByTaskID[task.id].map { now < $0.startAt } ?? false)

        switch run.sessionPhase {
        case .draft, .compiled:
            return .ready
        case .staging:
            return .compiling
        case .recovery:
            let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
            return recoveryDone ? .completed : .recovery
        case .completed:
            return .completed
        case .aborting, .aborted:
            let abortDone = run.taskMissionEndAbortCompletedByTaskID.contains(task.id)
                || Self.slotRollupMirrorsAutoMissionEndAckAbort(task: task, run: run)
            return abortDone ? .aborted : .aborting
        case .executing:
            if run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id) {
                let abortDone = run.taskMissionEndAbortCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckAbort(task: task, run: run)
                return abortDone ? .aborted : .aborting
            }
            if run.taskMissionEndAbortCompletedByTaskID.contains(task.id) {
                return .aborted
            }
            if run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id) {
                let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
                return recoveryDone ? .completed : .recovery
            }
            if run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id) {
                return .completed
            }
            if inDeferral { return .staging }
            if let rolled = Self.rollupMissionTaskStateFromSquads(task: task, run: run, now: now) {
                return rolled
            }
            if run.activeCycleTaskIDs.contains(task.id) { return .executing }
            let cyclesDone = run.taskCyclesCompletedByTaskID[task.id] ?? 0
            let repeats = task.regularity == .continuous || task.regularity == .continuousWithDelay
            if repeats, Self.finiteRepeatingCyclesExhausted(task: task, cyclesDone: cyclesDone) {
                let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
                return recoveryDone ? .completed : .recovery
            }
            if repeats, cyclesDone > 0 {
                // Task-level rollup: off-cycle gaps read **Executing** — between-cycle gaps are squad/roster scoped.
                return .executing
            }
            return .ready
        }
    }

    /// Finite continuous / continuous-with-delay: all allotted cycles have finished (`MissionTask/cycles` > 0).
    private static func finiteRepeatingCyclesExhausted(task: MissionTask, cyclesDone: Int) -> Bool {
        guard task.regularity == .continuous || task.regularity == .continuousWithDelay else { return false }
        guard task.cycles > 0 else { return false }
        return cyclesDone >= task.cycles
    }

    func appendEvent(_ event: MissionRunEvent) {
        events.append(event)
    }

    func setMissionCycleCount(_ count: Int) {
        cyclesCompleted = max(0, count)
    }

    /// Latest hub snapshot for abort-time move-to-point planning (nil without link services or a resolved stream id).
    func abortPlanningHubTelemetry(for assignment: MissionRunAssignment) -> FleetHubVehicleTelemetry? {
        guard let fleetLink, let sitl else { return nil }
        guard let vehicleID = resolvedFleetStreamVehicleID(
            assignment: assignment,
            fleetLink: fleetLink,
            sitl: sitl
        ) else { return nil }
        return fleetLink.hubTelemetry(forVehicleID: vehicleID)
    }

    /// Roster SIM teleport after run-complete cleanup; ``skipVehicleIDs`` is reserved for future gating (currently unused — teleport runs regardless of kill outcome).
    internal func performRosterSimHomeRestoreAfterSuccessfulCompletion(
        snapshots: [UUID: FleetSimState],
        fleetLink: FleetLinkService,
        sitl: SitlService,
        skipVehicleIDs: Set<String> = []
    ) async -> (applied: Int, skipped: Int) {
        var applied = 0
        var skipped = 0
        let ordered = snapshots.keys.sorted { $0.uuidString < $1.uuidString }
        for assignmentID in ordered {
            guard let state = snapshots[assignmentID],
                  let assignment = assignments.first(where: { $0.id == assignmentID })
            else { continue }
            guard let vehicleID = resolvedFleetStreamVehicleID(
                assignment: assignment,
                fleetLink: fleetLink,
                sitl: sitl
            ) else {
                skipped += 1
                continue
            }
            guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else {
                skipped += 1
                continue
            }
            let stack = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
                ?? fleetLink.hubTelemetryByVehicleID[vehicleID]?.autopilotStack
                ?? .unknown
            guard stack != .unknown else {
                skipped += 1
                continue
            }
            guard !skipVehicleIDs.contains(vehicleID) else {
                skipped += 1
                continue
            }
            await fleetLink.applySimState(
                vehicleID: vehicleID,
                state: state,
                autopilotStack: stack,
                source: "missioncontrol.run_complete_sim_cleanup.teleport"
            )
            applied += 1
        }
        if !snapshots.isEmpty {
            systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.lifecycleSimHomeRestoreBatch,
                templateParams: [
                    "phase": "roster",
                    "applied": "\(applied)",
                    "skipped": "\(skipped)",
                    "candidates": "\(snapshots.count)",
                ]
            )
        }
        return (applied, skipped)
    }

    /// Reserve pool SIM teleport after run-complete cleanup; ``skipVehicleIDs`` is reserved for future gating (currently unused).
    internal func performReservePoolSimHomeRestoreAfterSuccessfulCompletion(
        snapshots: [UUID: FleetSimState],
        fleetLink: FleetLinkService,
        sitl: SitlService,
        skipVehicleIDs: Set<String> = []
    ) async -> (applied: Int, skipped: Int) {
        var applied = 0
        var skipped = 0
        let ordered = snapshots.keys.sorted { $0.uuidString < $1.uuidString }
        for slotID in ordered {
            guard let state = snapshots[slotID],
                  let pair = reservePoolSlot(forSlotID: slotID)
            else { continue }
            let assignment = MissionRunAssignment.syntheticForReservePool(slot: pair.slot)
            guard let vehicleID = resolvedFleetStreamVehicleID(
                assignment: assignment,
                fleetLink: fleetLink,
                sitl: sitl
            ) else {
                skipped += 1
                continue
            }
            guard fleetLink.isGuardianManagedSitlStream(vehicleID: vehicleID) else {
                skipped += 1
                continue
            }
            let stack = fleetLink.vehicleModel(forVehicleID: vehicleID)?.data.telemetry?.autopilotStack
                ?? fleetLink.hubTelemetryByVehicleID[vehicleID]?.autopilotStack
                ?? .unknown
            guard stack != .unknown else {
                skipped += 1
                continue
            }
            guard !skipVehicleIDs.contains(vehicleID) else {
                skipped += 1
                continue
            }
            await fleetLink.applySimState(
                vehicleID: vehicleID,
                state: state,
                autopilotStack: stack,
                source: "missioncontrol.run_complete_sim_cleanup.teleport"
            )
            applied += 1
        }
        if !snapshots.isEmpty {
            systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.lifecycleSimHomeRestoreBatch,
                templateParams: [
                    "phase": "reserve_pool",
                    "applied": "\(applied)",
                    "skipped": "\(skipped)",
                    "candidates": "\(snapshots.count)",
                ]
            )
        }
        return (applied, skipped)
    }

}

// MARK: - Mission Preflight (roster + floating reserve pool)

extension MissionRunEnvironment {
    /// Deterministic Mission Preflight roster order: **all** roster assignments (same order as ``assignments``) unless a mission template is present — then ``orderedStartRunPreflightProbeSequence(mission:)`` groups by task for the sweep.
    ///
    /// **Floating reserve pool** berths are **excluded** by default so pool aircraft do not block mission start; **reserve swap-in** (MC-R confirm) runs hub snapshot gates then an arm probe via ``MissionControlStore/runSingleVehiclePreflightProbe(telemetryGateMode: .reserveSwapIn, allowDuringLiveMission:)``. Pass ``includeFloatingReservePoolSlots: true`` only for diagnostics or legacy tooling.
    ///
    /// Empty pool slots are never listed. Roster rows without a binding still appear so the sheet can show the same **no fleet vehicle** failure as before.
    func orderedStartRunPreflightProbeTargets(includeFloatingReservePoolSlots: Bool = false) -> [(identity: MissionRunPreflightSlotIdentity, displayTitle: String, assignment: MissionRunAssignment)] {
        var rows: [(identity: MissionRunPreflightSlotIdentity, displayTitle: String, assignment: MissionRunAssignment)] = []
        for assignment in assignments {
            rows.append((.rosterAssignment(assignment.id), assignment.slotName, assignment))
        }
        guard includeFloatingReservePoolSlots else { return rows }
        let taskNameByID = Dictionary(uniqueKeysWithValues: (template?.routeMacro.tasks ?? []).map { ($0.id, $0.name) })
        for taskID in reservePoolByTaskID.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let pool = reservePoolByTaskID[taskID] else { continue }
            let taskHeading = taskNameByID[taskID] ?? "Task"
            for slot in pool.entries where slot.hasFleetOrLegacyBinding {
                let synthetic = MissionRunAssignment.syntheticForReservePool(slot: slot)
                let title = "\(taskHeading) reserve · \(slot.label)"
                rows.append((.floatingReservePool(taskID: taskID, slotID: slot.id), title, synthetic))
            }
        }
        return rows
    }
}

// MARK: - Squad cycle state

extension MissionRunEnvironment {

    internal func clearSquadCycleTracking() {
        activeCycleSquadAssignmentIDs = []
        finishedMissionCycleVehicleIDsBySquadAssignmentID = [:]
        squadCyclesCompletedByAssignmentID = [:]
        if !squadStateByAssignmentID.isEmpty { squadStateByAssignmentID = [:] }
        if !deferredFirstWaveSquadAssignmentIDsByTaskID.isEmpty { deferredFirstWaveSquadAssignmentIDsByTaskID = [:] }
        if !squadStartDeferralByAssignmentID.isEmpty { squadStartDeferralByAssignmentID = [:] }
        if !squadCompletePolicyWindDownIssuedAssignmentIDs.isEmpty { squadCompletePolicyWindDownIssuedAssignmentIDs = [] }
        if !missionSquadOperatorPausedAssignmentIDs.isEmpty { missionSquadOperatorPausedAssignmentIDs = [] }
        if !missionSquadConvoyAssemblyHoldAssignmentIDs.isEmpty { missionSquadConvoyAssemblyHoldAssignmentIDs = [] }
        if !missionSquadFormationFollowHaltedPrimaryAssignmentIDs.isEmpty {
            missionSquadFormationFollowHaltedPrimaryAssignmentIDs = []
        }
        if squadFollowStatusRevision != 0 { squadFollowStatusRevision = 0 }
        if !missionRunRosterReleasedAssignmentIDs.isEmpty { missionRunRosterReleasedAssignmentIDs = [] }
    }

    internal func markMissionSquadAutostartSuppressed(forAssignmentID assignmentID: UUID) {
        missionSquadAutopilotAutostartSuppressedAssignmentIDs.insert(assignmentID)
        refreshDerivedTaskStates()
    }

    /// Operator **Park** on an in-flight primary squad: hold MAVLink autostart / stagger until **Continue mission**.
    func markMissionSquadOperatorPaused(
        forAssignmentID assignmentID: UUID,
        beginConvoyRebuildWhenPaused: Bool = true
    ) {
        var paused = missionSquadOperatorPausedAssignmentIDs
        guard paused.insert(assignmentID).inserted else {
            removeSquadFromActiveCycle(assignmentID)
            markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
            return
        }
        missionSquadOperatorPausedAssignmentIDs = paused
        removeSquadFromActiveCycle(assignmentID)
        markMissionSquadAutostartSuppressed(forAssignmentID: assignmentID)
        if beginConvoyRebuildWhenPaused, let ctx = effectiveExecutionContextForDispatch() {
            systems.squadFollow.beginConvoyRebuild(
                primaryAssignmentID: assignmentID,
                fleetLink: ctx.fleetLink,
                sitl: ctx.sitl,
                launchPrimaryWhenReady: false
            )
        }
    }

    /// Clears operator park hold after **Continue mission** (does not clear wind-down autostart suppress).
    func clearMissionSquadOperatorPaused(forAssignmentID assignmentID: UUID) {
        guard missionSquadOperatorPausedAssignmentIDs.remove(assignmentID) != nil else { return }
        if pendingMissionSquadGracefulWindDownKindByAssignmentID[assignmentID] == nil,
           !squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignmentID),
           !squadAbortPolicyWindDownIssuedAssignmentIDs.contains(assignmentID) {
            var suppressed = missionSquadAutopilotAutostartSuppressedAssignmentIDs
            suppressed.remove(assignmentID)
            missionSquadAutopilotAutostartSuppressedAssignmentIDs = suppressed
        }
        if let ctx = effectiveExecutionContextForDispatch() {
            systems.squadFollow.resumeConvoyAssemblyForPrimaryLaunch(
                primaryAssignmentID: assignmentID,
                fleetLink: ctx.fleetLink,
                sitl: ctx.sitl
            )
        }
        refreshDerivedTaskStates()
    }

    internal func registerDeferredFirstWaveSquads(taskID: UUID, assignmentIDs: [UUID]) {
        guard !assignmentIDs.isEmpty else { return }
        deferredFirstWaveSquadAssignmentIDsByTaskID[taskID] = assignmentIDs
    }

    internal func consumeNextDeferredFirstWaveSquadAssignmentID(forTaskID taskID: UUID) -> UUID? {
        guard var queue = deferredFirstWaveSquadAssignmentIDsByTaskID[taskID], !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        if queue.isEmpty {
            deferredFirstWaveSquadAssignmentIDsByTaskID.removeValue(forKey: taskID)
        } else {
            deferredFirstWaveSquadAssignmentIDsByTaskID[taskID] = queue
        }
        return next
    }

    internal func setSquadStartDeferral(_ value: MissionTaskStartDeferral?, forAssignmentID assignmentID: UUID) {
        if let value {
            squadStartDeferralByAssignmentID[assignmentID] = value
        } else {
            squadStartDeferralByAssignmentID.removeValue(forKey: assignmentID)
        }
        refreshDerivedTaskStates()
    }

    internal func shouldSuppressAutopilotAutostart(
        forSquadAssignmentID assignmentID: UUID,
        taskID: UUID,
        mission: Mission
    ) -> Bool {
        if unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission: mission).contains(taskID) {
            return true
        }
        if pendingMissionSquadGracefulWindDownKindByAssignmentID[assignmentID] != nil {
            return true
        }
        if missionSquadConvoyAssemblyHoldAssignmentIDs.contains(assignmentID) {
            return true
        }
        return missionSquadAutopilotAutostartSuppressedAssignmentIDs.contains(assignmentID)
    }

    internal func markMissionSquadConvoyAssemblyHold(forAssignmentID assignmentID: UUID) {
        guard missionSquadConvoyAssemblyHoldAssignmentIDs.insert(assignmentID).inserted else { return }
        refreshDerivedTaskStates()
    }

    internal func clearMissionSquadConvoyAssemblyHold(forAssignmentID assignmentID: UUID) {
        guard missionSquadConvoyAssemblyHoldAssignmentIDs.remove(assignmentID) != nil else { return }
        refreshDerivedTaskStates()
    }

    func isMissionSquadFormationFollowHalted(forAssignmentID assignmentID: UUID) -> Bool {
        missionSquadFormationFollowHaltedPrimaryAssignmentIDs.contains(assignmentID)
    }

    func wingmanFollowPhase(forAssignmentID assignmentID: UUID) -> MissionRunSquadWingmanFollowPhase? {
        systems.squadFollow.wingmanFollowPhase(forAssignmentID: assignmentID)
    }

    func bumpSquadFollowStatusRevision() {
        squadFollowStatusRevision &+= 1
    }

    func markMissionRunRosterReleasedFromSquadFollow(assignmentID: UUID) {
        missionRunRosterReleasedAssignmentIDs.insert(assignmentID)
    }

    /// Wingman stream reconnect budget exhausted — pause primary, suppress autostart, surface operator prompt.
    func reportFormationFollowStreamExhausted(
        primaryAssignmentID: UUID,
        failedWingmanAssignmentIDs: [UUID],
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard missionSquadFormationFollowHaltedPrimaryAssignmentIDs.insert(primaryAssignmentID).inserted else {
            return
        }
        markMissionSquadAutostartSuppressed(forAssignmentID: primaryAssignmentID)
        systems.executor.handleFormationFollowStreamExhausted(
            primaryAssignmentID: primaryAssignmentID,
            failedWingmanAssignmentIDs: failedWingmanAssignmentIDs,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    func clearMissionSquadFormationFollowHalt(forAssignmentID assignmentID: UUID) {
        guard missionSquadFormationFollowHaltedPrimaryAssignmentIDs.remove(assignmentID) != nil else { return }
        if pendingMissionSquadGracefulWindDownKindByAssignmentID[assignmentID] == nil,
           !squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignmentID),
           !squadAbortPolicyWindDownIssuedAssignmentIDs.contains(assignmentID),
           !missionSquadOperatorPausedAssignmentIDs.contains(assignmentID) {
            var suppressed = missionSquadAutopilotAutostartSuppressedAssignmentIDs
            suppressed.remove(assignmentID)
            missionSquadAutopilotAutostartSuppressedAssignmentIDs = suppressed
        }
        refreshDerivedTaskStates()
    }

    internal func resolvedTaskID(forSquadAssignmentID assignmentID: UUID, mission: Mission) -> UUID? {
        guard let row = assignments.first(where: { $0.id == assignmentID }) else { return nil }
        if let tid = row.taskId { return tid }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1 { return enabled.first?.id }
        return nil
    }

    internal func clearFinishedMissionCycleVehicleIDs(forSquadAssignmentID assignmentID: UUID) {
        finishedMissionCycleVehicleIDsBySquadAssignmentID.removeValue(forKey: assignmentID)
    }

    internal func markFinishedMissionCycleVehicleID(_ vehicleID: String, forSquadAssignmentID assignmentID: UUID) {
        var next = finishedMissionCycleVehicleIDsBySquadAssignmentID
        var bucket = next[assignmentID] ?? []
        bucket.insert(vehicleID)
        next[assignmentID] = bucket
        finishedMissionCycleVehicleIDsBySquadAssignmentID = next
    }

    internal func markSquadActiveInCurrentCycle(_ assignmentID: UUID) {
        guard activeCycleSquadAssignmentIDs.insert(assignmentID).inserted else { return }
        syncActiveCycleTaskIDsFromSquads()
        refreshDerivedTaskStates()
    }

    internal func removeSquadFromActiveCycle(_ assignmentID: UUID) {
        guard activeCycleSquadAssignmentIDs.remove(assignmentID) != nil else { return }
        syncActiveCycleTaskIDsFromSquads()
        refreshDerivedTaskStates()
    }

    internal func markFirstWaveSquadsActiveInCurrentCycle(taskID: UUID, mission: Mission) {
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskID }) else { return }
        let enabledCount = mission.routeMacro.tasks.filter(\.enabled).count
        let squads = MissionControlSquadUtilities.orderedPrimarySquads(
            task: task,
            assignments: assignments,
            rosterDevices: mission.rosterDevices,
            enabledTaskCount: enabledCount
        )
        for (index, squad) in squads.enumerated() {
            guard MissionTaskStaggerPolicy.includesSquadInAutomaticFirstWave(
                task: task,
                squadIndex: index
            ) else { continue }
            _ = activeCycleSquadAssignmentIDs.insert(squad.assignment.id)
        }
        syncActiveCycleTaskIDsFromSquads()
    }

    internal func recordSquadCycleCompletions(assignmentIDs: Set<UUID>, mission: Mission) -> Set<UUID> {
        guard !assignmentIDs.isEmpty else { return [] }
        for aid in assignmentIDs {
            squadCyclesCompletedByAssignmentID[aid, default: 0] += 1
        }
        let closed = recomputeAggregatedTaskCyclesAndReturnTasksWhoseCycleBoundaryClosed(mission: mission)
        refreshDerivedTaskStates()
        return closed
    }

    @discardableResult
    internal func recomputeAggregatedTaskCyclesAndReturnTasksWhoseCycleBoundaryClosed(mission: Mission) -> Set<UUID> {
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        var closedTaskIDs: Set<UUID> = []
        for task in enabled {
            let enabledCount = enabled.count
            let squads = MissionControlSquadUtilities.orderedPrimarySquads(
                task: task,
                assignments: assignments,
                rosterDevices: mission.rosterDevices,
                enabledTaskCount: enabledCount
            )
            guard !squads.isEmpty else { continue }
            let counts = squads.map { squadCyclesCompletedByAssignmentID[$0.assignment.id] ?? 0 }
            let rolled = counts.min() ?? 0
            let previous = taskCyclesCompletedByTaskID[task.id] ?? 0
            taskCyclesCompletedByTaskID[task.id] = rolled
            let allMatch = counts.allSatisfy { $0 == rolled }
            let noneInFlight = !squads.contains { activeCycleSquadAssignmentIDs.contains($0.assignment.id) }
            if rolled > previous, allMatch, noneInFlight, rolled > 0 {
                closedTaskIDs.insert(task.id)
            }
        }
        return closedTaskIDs
    }

    internal func syncActiveCycleTaskIDsFromSquads() {
        guard let mission = template else {
            if !activeCycleTaskIDs.isEmpty { activeCycleTaskIDs = [] }
            return
        }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        var taskIDs: Set<UUID> = []
        for assignmentID in activeCycleSquadAssignmentIDs {
            guard let row = assignments.first(where: { $0.id == assignmentID }) else { continue }
            if let tid = row.taskId {
                taskIDs.insert(tid)
            } else if enabled.count == 1, let only = enabled.first {
                taskIDs.insert(only.id)
            }
        }
        if taskIDs != activeCycleTaskIDs {
            activeCycleTaskIDs = taskIDs
        }
    }

    func primarySquads(forTaskID taskID: UUID, mission: Mission? = nil) -> [(assignment: MissionRunAssignment, squadIndex: Int)] {
        let source = mission ?? template
        guard let mission = source,
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID })
        else { return [] }
        let enabledCount = mission.routeMacro.tasks.filter(\.enabled).count
        return MissionControlSquadUtilities.orderedPrimarySquads(
            task: task,
            assignments: assignments,
            rosterDevices: mission.rosterDevices,
            enabledTaskCount: enabledCount
        ).enumerated().map { (assignment: $0.element.assignment, squadIndex: $0.offset) }
    }

    func boundPrimarySquadCount(forTaskID taskID: UUID, mission: Mission? = nil) -> Int {
        primarySquads(forTaskID: taskID, mission: mission).count
    }

    func refreshDerivedSquadStates(now: Date = Date()) {
        guard let mission = template else {
            if !squadStateByAssignmentID.isEmpty { squadStateByAssignmentID = [:] }
            return
        }
        var next: [UUID: MissionSquadState] = [:]
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        for task in enabled {
            let squads = primarySquads(forTaskID: task.id, mission: mission)
            for squad in squads {
                next[squad.assignment.id] = Self.deriveMissionSquadState(
                    task: task,
                    assignment: squad.assignment,
                    squadIndex: squad.squadIndex,
                    run: self,
                    now: now
                )
            }
        }
        for (assignmentID, state) in next {
            switch state {
            case .completed:
                markSquadMissionEndRecoveryCompleted(forAssignmentID: assignmentID)
            case .aborted:
                markSquadMissionEndAbortCompleted(forAssignmentID: assignmentID)
            default:
                break
            }
        }
        if next != squadStateByAssignmentID {
            squadStateByAssignmentID = next
        }
    }

    /// Terminal squad states (v1 lock): once ``.completed`` / ``.aborted``, derivation does not regress for task-wide flags or rollup.
    private static func stickyTerminalMissionSquadStateIfAny(
        assignment: MissionRunAssignment,
        run: MissionRunEnvironment
    ) -> MissionSquadState? {
        if run.squadMissionEndRecoveryCompletedByAssignmentIDs.contains(assignment.id) {
            return .completed
        }
        if run.squadMissionEndAbortCompletedByAssignmentIDs.contains(assignment.id) {
            return .aborted
        }
        switch run.squadStateByAssignmentID[assignment.id] {
        case .completed:
            return .completed
        case .aborted:
            return .aborted
        default:
            return nil
        }
    }

    static func deriveMissionSquadState(
        task: MissionTask,
        assignment: MissionRunAssignment,
        squadIndex: Int,
        run: MissionRunEnvironment,
        now: Date
    ) -> MissionSquadState {
        if !task.enabled { return .ready }
        if let terminal = stickyTerminalMissionSquadStateIfAny(assignment: assignment, run: run) {
            return terminal
        }

        let inDeferral = task.enabled
            && (run.status == .running || run.status == .paused)
            && (run.taskStartDeferralByTaskID[task.id].map { now < $0.startAt } ?? false)

        switch run.sessionPhase {
        case .draft, .compiled:
            return .ready
        case .staging:
            return .staging
        case .recovery, .completed:
            let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                || run.squadMissionEndRecoveryCompletedByAssignmentIDs.contains(assignment.id)
                || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
            return recoveryDone ? .completed : .recovery
        case .aborting, .aborted:
            let abortDone = run.taskMissionEndAbortCompletedByTaskID.contains(task.id)
                || run.squadMissionEndAbortCompletedByAssignmentIDs.contains(assignment.id)
                || Self.slotRollupMirrorsAutoMissionEndAckAbort(task: task, run: run)
            return abortDone ? .aborted : .aborting
        case .executing:
            if run.squadAbortPolicyWindDownIssuedAssignmentIDs.contains(assignment.id) {
                let abortDone = run.squadMissionEndAbortCompletedByAssignmentIDs.contains(assignment.id)
                    || run.taskMissionEndAbortCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckAbort(task: task, run: run)
                return abortDone ? .aborted : .aborting
            }
            if run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignment.id) {
                let recoveryDone = run.squadMissionEndRecoveryCompletedByAssignmentIDs.contains(assignment.id)
                    || run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
                return recoveryDone ? .completed : .recovery
            }
            if run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id) {
                let abortDone = run.taskMissionEndAbortCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckAbort(task: task, run: run)
                return abortDone ? .aborted : .aborting
            }
            if run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id) {
                let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
                return recoveryDone ? .completed : .recovery
            }
            if inDeferral
                || (run.squadStartDeferralByAssignmentID[assignment.id].map { now < $0.startAt } ?? false) {
                return .staging
            }
            if run.missionSquadOperatorPausedAssignmentIDs.contains(assignment.id) {
                return .paused
            }
            if run.activeCycleSquadAssignmentIDs.contains(assignment.id) { return .executing }
            let cyclesDone = run.squadCyclesCompletedByAssignmentID[assignment.id] ?? 0
            let repeats = task.regularity == .continuous || task.regularity == .continuousWithDelay
            if repeats, Self.finiteRepeatingSquadCyclesExhausted(task: task, cyclesDone: cyclesDone) {
                let recoveryDone = run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id)
                    || Self.slotRollupMirrorsAutoMissionEndAckRecovery(task: task, run: run)
                return recoveryDone ? .completed : .recovery
            }
            if repeats, cyclesDone > 0 {
                if task.regularity == .continuousWithDelay { return .between }
                return .executing
            }
            return .ready
        }
    }

    private static func finiteRepeatingSquadCyclesExhausted(task: MissionTask, cyclesDone: Int) -> Bool {
        guard task.regularity == .continuous || task.regularity == .continuousWithDelay else { return false }
        guard task.cycles > 0 else { return false }
        return cyclesDone >= task.cycles
    }

    /// Multi-primary task rollup from precomputed per-squad states.
    ///
    /// **Product lock** (`MRESquadsToDo.md` — **Auto pipeline**): whole-run / task auto wind-down follows
    /// **recovery → complete** among squads unless **every** primary is `.aborting` or `.aborted`; squads already on
    /// the abort path are **ignored** when deciding that branch among the rest (mixed abort + recovery still yields
    /// **recovery** until unanimity on abort).
    static func rollupMissionTaskStateFromSquadStates(_ states: [MissionSquadState]) -> MissionTaskState? {
        guard states.count > 1 else { return nil }
        let abortDirected: Set<MissionSquadState> = [.aborting, .aborted]
        if states.allSatisfy({ abortDirected.contains($0) }) {
            if states.allSatisfy({ $0 == .aborted }) { return .aborted }
            return .aborting
        }
        let active = states.filter { !abortDirected.contains($0) }
        guard !active.isEmpty else { return .executing }
        return rollupMissionTaskStateFromNonAbortSquadStates(active)
    }

    static func rollupMissionTaskStateFromSquads(
        task: MissionTask,
        run: MissionRunEnvironment,
        now: Date
    ) -> MissionTaskState? {
        let squads = run.primarySquads(forTaskID: task.id)
        guard squads.count > 1 else { return nil }
        let states = squads.map {
            deriveMissionSquadState(
                task: task,
                assignment: $0.assignment,
                squadIndex: $0.squadIndex,
                run: run,
                now: now
            )
        }
        return rollupMissionTaskStateFromSquadStates(states)
    }

    /// Priority order for squads after removing `.aborting` / `.aborted` (see ``rollupMissionTaskStateFromSquadStates``).
    ///
    /// **Finite multi-primary “race”:** the task stays ``executing`` while **any** primary is still in a contesting state
    /// (executing, between-cycle gap, start deferral, or not yet started). Task ``recovery`` applies only when no squad
    /// is still contesting and at least one remains in ``recovery`` (others may already be ``completed`` after ack).
    private static func rollupMissionTaskStateFromNonAbortSquadStates(_ states: [MissionSquadState]) -> MissionTaskState {
        if states.allSatisfy({ $0 == .completed }) { return .completed }
        if states.allSatisfy({ $0 == .ready }) { return .ready }
        if states.allSatisfy({ $0 == .staging }) { return .staging }

        let stillContest: Set<MissionSquadState> = [.executing, .between, .staging, .ready, .paused]
        if states.contains(where: { stillContest.contains($0) }) {
            return .executing
        }
        if states.contains(.recovery) { return .recovery }
        return .executing
    }
}

// MARK: - Log template keys (task-force state)

extension MissionRunLogTemplateKey {
    static let taskForceStateChanged = "missioncontrol.mre.task.taskforce_state"
    static let operatorMarkedMissionTaskTriageState = "missioncontrol.mre.operator.marked_task_triage_state"
    /// §3 auto triage: one consolidated line per ``applySlotEvidenceAutoMissionEndAckIfNeeded`` pass; ``templateParams``: `abortTasks`, `recoveryTasks` (use `—` when that side had no auto-ack).
    static let slotEvidenceAutoAcknowledgedMissionEndBatch = "missioncontrol.mre.slot_evidence.auto_ack_mission_end_batch"

    // Mission points (run envelope; see ``MissionRunEnvironment/runtimeMissionPoints``)
    static let missionPointRuntimeSeeded = "missioncontrol.mre.point.runtime_seeded"
    static let missionPointRuntimeCreated = "missioncontrol.mre.point.runtime_created"
    static let missionPointRuntimeUpdated = "missioncontrol.mre.point.runtime_updated"
    static let missionPointRuntimeClosedChanged = "missioncontrol.mre.point.runtime_closed_changed"
    /// Floating reserve drawn into a roster slot (operator or automation); ``templateParams``: `slot`, `slotID`, `poolSlotID`, `source`.
    static let floatingReserveSwapEngaged = "missioncontrol.mre.reserve.swap_engaged"
    /// Fixed template reserve roster row swapped with a primary/wingman vacancy; ``templateParams``: `vacancySlot`, `vacancySlotID`, `reserveSlot`, `reserveSlotID`, `source`.
    static let fixedRosterReserveSwapEngaged = "missioncontrol.mre.reserve.fixed_roster_swap_engaged"

    /// MCS staging map: operator used **Set reserve pool home**; ``templateParams``: `sent`, `latDeg`, `lonDeg` (``taskID`` injected by ``MissionRunEvent`` init).
    static let mcsReservePoolHomeMapBatch = "missioncontrol.mcs.setup.reserve_pool_home_map_batch"
}


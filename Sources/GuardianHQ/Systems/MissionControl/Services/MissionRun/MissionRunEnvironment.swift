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

    /// Latest execution context from start/cycle ingest; required for queued dispatch and observer enqueue APIs.
    private(set) var lastExecutionContext: MissionRunExecutionContext?

    /// Resolved roster **behavior** roles for the current template / last execution mission (``ResolvedRosterRole``).
    /// Refreshed from ``Mission`` in ``captureExecutionContext(_:)``, ``updateTemplate(_:)``, and run init.
    private(set) var rosterRoleResolutionsByDeviceID: [UUID: ResolvedRosterRole] = [:]

    /// Live **mission points** envelope for this run (rally / extraction / …): seeded from the mission template,
    /// then mutated by operator / MRE / plugins without rewriting the saved ``Mission`` document (see README **Mission template points**).
    ///
    /// While ``status`` is ``MissionRunStatus/setup``, ``updateTemplate(_:)`` re-syncs from ``Mission/missionPoints`` so
    /// authoring changes flow in. After the run leaves setup, this array is **not** replaced from the template—only
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
    @Published private(set) var finishedMissionCycleVehicleIDs: Set<String> = []
    @Published private(set) var activeCycleTaskIDs: Set<UUID> = []
    /// Completed autopilot cycles per task this run (continuous / continuous-with-delay). Used with ``MissionTask/cycles``.
    private(set) var taskCyclesCompletedByTaskID: [UUID: Int] = [:]

    /// Operator (or future automation) confirms this task’s roster finished the post-mission **recovery** protocol; then UI shows ``MissionTaskState/completed`` for that task while the run may still be active.
    @Published private(set) var taskMissionEndRecoveryCompletedByTaskID: Set<UUID> = []

    /// Operator (or future automation) confirms this task’s roster finished the **abort** protocol while the run is in ``MissionRunSessionPhase/aborting`` or ``MissionRunSessionPhase/aborted``.
    @Published private(set) var taskMissionEndAbortCompletedByTaskID: Set<UUID> = []

    /// Derived per-task state for MC-R UI (refreshed when run scheduling / lifecycle inputs change).
    @Published private(set) var taskStateByTaskID: [UUID: MissionTaskState] = [:]

    /// Derived per-task **attempting** intent (abort/complete protocol scheduled or wind-down issued). Co-refreshed with ``taskStateByTaskID`` in ``refreshDerivedTaskStates()`` — v1 uses orchestration flags only; see README **Task attempting vs current**.
    @Published private(set) var taskAttemptingByTaskID: [UUID: MissionTaskAttemptState] = [:]

    /// Operator triage terminal state for a task (``.aborted`` / ``.completed``). ``deriveMissionTaskState`` returns this verbatim so refresh cannot override the operator’s choice.
    @Published private(set) var operatorTriageMarkedMissionTaskStateByTaskID: [UUID: MissionTaskState] = [:]

    /// Optional **floating** reserve **slots** per task (MCS-only run envelope; not persisted on ``Mission`` templates).
    /// See **README.md** → **Floating reserve pool (Mission Control run)**.
    @Published private(set) var reservePoolByTaskID: [UUID: MissionRunReservePool] = [:]

    /// Fleet vehicles (``FleetMissionVehicleToken/storageKey``) the operator has **written off** for reserve-pool selection for this run — **airframe** state, not slot state.
    @Published private(set) var writtenOffFleetVehicleStorageKeysForReservePool: Set<String> = []

    /// Task-scoped graceful wind-down scheduled for the next shared autopilot cycle boundary (see scheduling APIs).
    @Published private(set) var pendingMissionTaskGracefulWindDownKindByTaskID: [UUID: MissionRunMissionTaskGracefulPendingKind] = [:]

    /// Fleet abort-policy commands were dispatched for this task (immediate or end-of-cycle); cleared when abort protocol is acknowledged.
    @Published private(set) var missionTaskAbortWindDownIssuedTaskIDs: Set<UUID> = []

    /// Complete-policy wind-down was dispatched for this task; cleared when recovery protocol is acknowledged.
    @Published private(set) var missionTaskCompleteWindDownIssuedTaskIDs: Set<UUID> = []

    /// Tasks that must not receive automatic next-cycle MAVLink starts after a task-scoped wind-down.
    @Published private(set) var missionTaskAutopilotAutostartSuppressedTaskIDs: Set<UUID> = []

    internal weak var fleetLink: FleetLinkService?
    internal weak var sitl: SitlService?
    private var assistantsByKey: [String: AnyObject] = [:]
    let systems: MissionRunSystems

    /// Persists template mutations performed via ``MissionRunEnvironment`` policy / Rules-of-Engagement APIs.
    /// Set by the layer that owns the ``MissionStore`` (typically ``MissionRunDetailView``); when `nil`,
    /// mission/task edits are still applied to the in-memory ``template`` but won't survive a template refresh.
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
            policyAuthority: MissionRunPolicyAuthoritySubsystem()
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

    func attachServices(fleetLink: FleetLinkService, sitl: SitlService) {
        self.fleetLink = fleetLink
        self.sitl = sitl
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
        guard status == .running else { return nil }
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

    // MARK: - Task-scoped mission wind-down (abort / complete)

    /// Assignments whose compiled or explicit ``MissionRunAssignment/taskId`` maps to `taskID`.
    func assignmentsBoundToMissionTask(taskID: UUID) -> [MissionRunAssignment] {
        assignments.filter { assignment in
            if assignment.taskId == taskID { return true }
            guard let plan = compiledPlan else { return false }
            return plan.roleTracks.contains { $0.assignmentID == assignment.id && $0.taskID == taskID }
        }
    }

    /// Clears task-scoped graceful scheduling, dispatch markers, and autostart suppression (whole-run start / reset).
    internal func clearMissionTaskScopedOrchestrationState() {
        if !pendingMissionTaskGracefulWindDownKindByTaskID.isEmpty {
            pendingMissionTaskGracefulWindDownKindByTaskID = [:]
        }
        if !missionTaskAbortWindDownIssuedTaskIDs.isEmpty { missionTaskAbortWindDownIssuedTaskIDs = [] }
        if !missionTaskCompleteWindDownIssuedTaskIDs.isEmpty { missionTaskCompleteWindDownIssuedTaskIDs = [] }
        if !missionTaskAutopilotAutostartSuppressedTaskIDs.isEmpty { missionTaskAutopilotAutostartSuppressedTaskIDs = [] }
        if !operatorTriageMarkedMissionTaskStateByTaskID.isEmpty { operatorTriageMarkedMissionTaskStateByTaskID = [:] }
    }

    internal func setPendingMissionTaskGracefulWindDown(kind: MissionRunMissionTaskGracefulPendingKind, forTaskID taskID: UUID) {
        pendingMissionTaskGracefulWindDownKindByTaskID[taskID] = kind
        refreshDerivedTaskStates()
    }

    internal func clearPendingMissionTaskGracefulWindDown(forTaskID taskID: UUID? = nil) {
        if let taskID {
            pendingMissionTaskGracefulWindDownKindByTaskID.removeValue(forKey: taskID)
        } else {
            pendingMissionTaskGracefulWindDownKindByTaskID.removeAll()
        }
        refreshDerivedTaskStates()
    }

    internal func consumePendingMissionTaskGracefulWindDown(forTaskID taskID: UUID) -> MissionRunMissionTaskGracefulPendingKind? {
        let v = pendingMissionTaskGracefulWindDownKindByTaskID.removeValue(forKey: taskID)
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

    /// When the operator explicitly starts a task cycle again, allow autostart bookkeeping and prior task-scoped markers to reset for that path.
    internal func prepareMissionTaskForOperatorRestart(taskID: UUID) {
        clearPendingMissionTaskGracefulWindDown(forTaskID: taskID)
        missionTaskAutopilotAutostartSuppressedTaskIDs.remove(taskID)
        missionTaskAbortWindDownIssuedTaskIDs.remove(taskID)
        missionTaskCompleteWindDownIssuedTaskIDs.remove(taskID)
        taskMissionEndRecoveryCompletedByTaskID.remove(taskID)
        taskMissionEndAbortCompletedByTaskID.remove(taskID)
        var triage = operatorTriageMarkedMissionTaskStateByTaskID
        triage.removeValue(forKey: taskID)
        operatorTriageMarkedMissionTaskStateByTaskID = triage
        refreshDerivedTaskStates()
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
        default:
            break
        }

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

        refreshDerivedTaskStates()
        if state == .aborted {
            promoteSessionPhaseToAbortedIfAllTasksAcknowledgedAbort()
        }
    }

    @discardableResult
    func abortMissionTask(_ target: MissionRunCommandTarget) -> Bool {
        guard case .task = target else { return false }
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
        guard case .task(let taskID) = target else { return false }
        guard status == .running || status == .paused else { return false }
        guard sessionPhase == .executing else { return false }
        systems.scheduling.abortMissionTaskAfterCycle(target: target)
        return pendingMissionTaskGracefulWindDownKindByTaskID[taskID] != nil
    }

    @discardableResult
    func completeMissionTask(_ target: MissionRunCommandTarget) -> Bool {
        guard case .task = target else { return false }
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
        guard case .task(let taskID) = target else { return false }
        guard status == .running || status == .paused else { return false }
        guard sessionPhase == .executing else { return false }
        systems.scheduling.completeMissionTaskAfterCycle(target: target)
        return pendingMissionTaskGracefulWindDownKindByTaskID[taskID] != nil
    }

    /// Cancels a previously scheduled per-task end-of-cycle wind-down for one task (or all tasks if `taskID` is nil).
    func revokeMissionTaskGracefulWindDown(forTaskID taskID: UUID? = nil) {
        systems.scheduling.revokeMissionTaskGracefulWindDown(forTaskID: taskID)
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
            writtenOffFleetVehicleStorageKeysForReservePool = []
        }
        refreshDerivedTaskStates()
    }

    // MARK: - Floating reserve pool (MCS / MRE)

    func setReservePool(_ pool: MissionRunReservePool, forTaskID taskID: UUID) {
        var next = reservePoolByTaskID
        next[taskID] = pool
        reservePoolByTaskID = next
    }

    func clearReservePool(forTaskID taskID: UUID) {
        var next = reservePoolByTaskID
        next.removeValue(forKey: taskID)
        reservePoolByTaskID = next
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
            return ("No bound reserves", appendBenchHint("Bind aircraft to floating reserve berths on this task."))
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
                appendBenchHint("All floating reserve aircraft on this task are written off for this run.")
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
                appendBenchHint("Pool aircraft on this task cannot be drawn (written off, battery or lifecycle, or hub link).")
            )
        }
        if classIgnoreDeduped.isEmpty {
            return (
                "No other reserves",
                appendBenchHint("Every pool aircraft already shares this slot’s fleet binding.")
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
                    appendBenchHint("Every class-matched pool aircraft already shares this slot’s fleet binding.")
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
        assignments = next

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

        assignments = nextAssignments
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
    private func fixedRosterReserveSwapPreCommitDedupeAndOperationalHold(
        vacancy: MissionRunAssignment,
        reserve: MissionRunAssignment
    ) -> Bool {
        if floatingReservePriorBindingRejectedIfReturnedToPoolBerth(vacancy) != nil {
            return false
        }

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
            if !missionRunFleetBindingPassesReservePoolOperationalDrawGate(fleetStorageKey: vacKey) { return false }
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
        finishedMissionCycleVehicleIDs.removeAll()
    }

    internal func markFinishedMissionCycleVehicleID(_ vehicleID: String) {
        finishedMissionCycleVehicleIDs.insert(vehicleID)
    }

    internal func clearActiveCycleTasks() {
        activeCycleTaskIDs.removeAll()
        refreshDerivedTaskStates()
    }

    internal func markTaskActiveInCurrentCycle(_ taskID: UUID) {
        activeCycleTaskIDs.insert(taskID)
        refreshDerivedTaskStates()
    }

    internal func clearTaskCycleCompletionCounts() {
        taskCyclesCompletedByTaskID.removeAll()
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

    /// When every **enabled** task has acknowledged the abort protocol, move session from ``MissionRunSessionPhase/aborting`` → ``MissionRunSessionPhase/aborted`` (run stays ``MissionRunStatus/running`` or ``MissionRunStatus/paused`` until the operator marks complete).
    private func promoteSessionPhaseToAbortedIfAllTasksAcknowledgedAbort() {
        guard (status == .running || status == .paused), sessionPhase == .aborting,
              let mission = template
        else { return }
        let enabledIDs = Set(mission.routeMacro.tasks.filter(\.enabled).map(\.id))
        guard enabledIDs.isSubset(of: taskMissionEndAbortCompletedByTaskID) else { return }
        setSessionPhase(.aborted)
    }

    internal func recordTaskCycleCompletions(forTaskIDs taskIDs: Set<UUID>) {
        for id in taskIDs {
            taskCyclesCompletedByTaskID[id, default: 0] += 1
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
        guard let mission = template else {
            if !taskStateByTaskID.isEmpty { taskStateByTaskID = [:] }
            if !taskAttemptingByTaskID.isEmpty { taskAttemptingByTaskID = [:] }
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
            if let attempting = Self.deriveMissionTaskAttemptState(task: task, run: self) {
                nextAttempting[task.id] = attempting
            }
        }
        if nextAttempting != taskAttemptingByTaskID {
            taskAttemptingByTaskID = nextAttempting
        }
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

    /// v1: abort wind-down **issued** wins over complete **issued**; **issued** wins over graceful **pending** only.
    private static func deriveMissionTaskAttemptState(task: MissionTask, run: MissionRunEnvironment) -> MissionTaskAttemptState? {
        guard task.enabled else { return nil }
        if let pinned = run.operatorTriageMarkedMissionTaskStateByTaskID[task.id],
           pinned == .aborted || pinned == .completed {
            return nil
        }
        if run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id) {
            return .abortWindDownIssued
        }
        if run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id) {
            return .recoveryWindDownIssued
        }
        if run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id] == .abortAfterCycle {
            return .abortWindDownScheduledAfterCycle
        }
        if run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id] == .completeAfterCycle {
            return .recoveryWindDownScheduledAfterCycle
        }
        return nil
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
                return run.taskMissionEndAbortCompletedByTaskID.contains(task.id) ? .aborted : .aborting
            }
            return .completed
        case .recovery:
            if run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id) { return .completed }
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
            return .recovery
        case .completed:
            return .completed
        case .aborting, .aborted:
            return run.taskMissionEndAbortCompletedByTaskID.contains(task.id) ? .aborted : .aborting
        case .executing:
            if run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id) {
                return run.taskMissionEndAbortCompletedByTaskID.contains(task.id) ? .aborted : .aborting
            }
            if run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id) {
                return run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id) ? .completed : .recovery
            }
            if inDeferral { return .staging }
            if run.activeCycleTaskIDs.contains(task.id) { return .executing }
            let cyclesDone = run.taskCyclesCompletedByTaskID[task.id] ?? 0
            let repeats = task.regularity == .continuous || task.regularity == .continuousWithDelay
            if repeats, Self.finiteRepeatingCyclesExhausted(task: task, cyclesDone: cyclesDone) {
                return run.taskMissionEndRecoveryCompletedByTaskID.contains(task.id) ? .completed : .recovery
            }
            if repeats, cyclesDone > 0 { return .between }
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

// MARK: - Log template keys (task-force state)

extension MissionRunLogTemplateKey {
    static let taskForceStateChanged = "missioncontrol.mre.task.taskforce_state"
    static let operatorMarkedMissionTaskTriageState = "missioncontrol.mre.operator.marked_task_triage_state"

    // Mission points (run envelope; see ``MissionRunEnvironment/runtimeMissionPoints``)
    static let missionPointRuntimeSeeded = "missioncontrol.mre.point.runtime_seeded"
    static let missionPointRuntimeCreated = "missioncontrol.mre.point.runtime_created"
    static let missionPointRuntimeUpdated = "missioncontrol.mre.point.runtime_updated"
    static let missionPointRuntimeClosedChanged = "missioncontrol.mre.point.runtime_closed_changed"
    /// Floating reserve drawn into a roster slot (operator or automation); ``templateParams``: `slot`, `slotID`, `poolSlotID`, `source`.
    static let floatingReserveSwapEngaged = "missioncontrol.mre.reserve.swap_engaged"
    /// Fixed template reserve roster row swapped with a primary/wingman vacancy; ``templateParams``: `vacancySlot`, `vacancySlotID`, `reserveSlot`, `reserveSlotID`, `source`.
    static let fixedRosterReserveSwapEngaged = "missioncontrol.mre.reserve.fixed_roster_swap_engaged"
}


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

    /// Operator triage terminal state for a task (``.aborted`` / ``.completed``). ``deriveMissionTaskState`` returns this verbatim so refresh cannot override the operator’s choice.
    @Published private(set) var operatorTriageMarkedMissionTaskStateByTaskID: [UUID: MissionTaskState] = [:]

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
        let rows = rosterRoleResolutionsByDeviceID.values.filter { $0.role != .none }
        guard !rows.isEmpty else { return }
        let summary = rows
            .map { "\($0.slotLabel):\($0.role.rawValue)" }
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
        } else {
            rosterRoleResolutionsByDeviceID = [:]
        }
        refreshDerivedTaskStates()
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

}

// MARK: - Log template keys (task-force state)

extension MissionRunLogTemplateKey {
    static let taskForceStateChanged = "missioncontrol.mre.task.taskforce_state"
    static let operatorMarkedMissionTaskTriageState = "missioncontrol.mre.operator.marked_task_triage_state"
}


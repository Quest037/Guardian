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
    @Published var pendingGracefulCycleStop: Bool
    @Published var reportCyclesCompleted: Int?
    @Published var completionKind: MissionRunCompletionKind?
    @Published var policies: MissionRunPolicies = MissionRunPolicies()

    /// Latest execution context from start/cycle ingest; required for queued dispatch and observer enqueue APIs.
    private(set) var lastExecutionContext: MissionRunExecutionContext?

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

    /// Operator (or future automation) confirms this task’s roster finished the **abort** protocol after a failed run (`MissionRunSessionPhase/failed`).
    @Published private(set) var taskMissionEndAbortCompletedByTaskID: Set<UUID> = []

    /// Derived per-task state for MC-R UI (refreshed when run scheduling / lifecycle inputs change).
    @Published private(set) var taskStateByTaskID: [UUID: MissionTaskState] = [:]

    internal weak var fleetLink: FleetLinkService?
    internal weak var sitl: SitlService?
    private var assistantsByKey: [String: AnyObject] = [:]
    let systems: MissionRunSystems

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
            scheduling: MissionRunSchedulingSubsystem()
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
        self.pendingGracefulCycleStop = false
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
        refreshDerivedTaskStates()
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
        pendingGracefulCycleStop: Bool = false,
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
        self.pendingGracefulCycleStop = pendingGracefulCycleStop
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
        guard !taskMissionEndRecoveryCompletedByTaskID.contains(taskID) else { return }
        var next = taskMissionEndRecoveryCompletedByTaskID
        next.insert(taskID)
        taskMissionEndRecoveryCompletedByTaskID = next
        refreshDerivedTaskStates()
    }

    func acknowledgeTaskMissionEndAbort(taskID: UUID) {
        guard !taskMissionEndAbortCompletedByTaskID.contains(taskID) else { return }
        var next = taskMissionEndAbortCompletedByTaskID
        next.insert(taskID)
        taskMissionEndAbortCompletedByTaskID = next
        refreshDerivedTaskStates()
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

    func startDelayMinutes(forTask taskId: UUID, mission: Mission? = nil) -> Int {
        if let t = taskStartDelays.first(where: { $0.taskId == taskId }) {
            return min(59, max(0, t.startDelayMinutes))
        }
        let source = mission ?? template
        if let mission = source,
           let task = mission.routeMacro.tasks.first(where: { $0.id == taskId }) {
            return min(59, max(0, task.startDelay))
        }
        return 0
    }

    func beginRun() {
        status = .running
        if startedAt == nil {
            startedAt = Date()
        }
        completedAt = nil
        pendingGracefulCycleStop = false
        completionKind = nil
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
            let message =
                "Mission Control is putting the task force for task “\(task.name)” into \(newState.displayTitle) state (was \(oldState.displayTitle)). Individual roster vehicles will confirm their own modes separately."
            systems.logging.appendLogEvent(
                level: .info,
                taskID: task.id,
                taskLabel: task.name,
                speaker: .missionControl,
                message: message,
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

        switch run.status {
        case .completed:
            if run.sessionPhase == .failed {
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
            case .executing, .recovery, .completed, .failed: return .ready
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
        case .failed:
            return run.taskMissionEndAbortCompletedByTaskID.contains(task.id) ? .aborted : .aborting
        case .executing:
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
}


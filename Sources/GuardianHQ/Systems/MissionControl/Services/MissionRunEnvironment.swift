import Combine
import Foundation
import Mavsdk

@MainActor
protocol MissionRunPlanningAssistant: AnyObject {
    func missionRun(
        _ run: MissionRunEnvironment,
        planning mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        applyingTo draftPlan: MissionControlPlan
    ) -> MissionControlPlan
}

@MainActor
protocol MissionRunPlanningMutationAssistant: AnyObject {
    func missionRun(
        _ run: MissionRunEnvironment,
        planning mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        shouldApply mutation: MissionControlPlanMutation
    ) -> MissionControlPlanMutation?

    func missionRun(
        _ run: MissionRunEnvironment,
        planning mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        didApply result: MissionControlPlanChangeResult
    )
}

@MainActor
protocol MissionRunAbortPlanningAssistant: AnyObject {
    func missionRun(_ run: MissionRunEnvironment, adjustingAbortPlan plan: MissionRunAbortPlan) -> MissionRunAbortPlan
}

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
    @Published var scheduleMode: MissionRunScheduleMode
    @Published var oneOffStartAt: Date?
    @Published var loopIntervalMinutes: Int
    @Published var loopRepeatCount: Int
    @Published var pathLoopTimings: [PathLoopTiming]
    @Published var pathStartDelays: [PathStartDelay]
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

    /// Per-path delayed restart windows (loop / continuous).
    @Published private(set) var cycleIntermissionByPathID: [UUID: MissionCycleIntermission] = [:]

    /// Per-path delayed initial mission starts.
    @Published private(set) var pathStartDeferralByPathID: [UUID: MissionPathStartDeferral] = [:]

    /// One-off deferred start countdown.
    @Published private(set) var oneOffDeferredExecution: MissionOneOffDeferredExecution?

    @Published private(set) var cyclesCompleted: Int = 0
    @Published private(set) var events: [MissionRunEvent] = []
    @Published private(set) var template: Mission?
    @Published private(set) var compiledPlan: MissionControlPlan?

    fileprivate weak var fleetLink: FleetLinkService?
    fileprivate weak var sitl: SitlService?
    private var assistantsByKey: [String: AnyObject] = [:]
    let systems: MissionRunSystems

    init(
        id: UUID = UUID(),
        mission: Mission,
        scheduleMode: MissionRunScheduleMode = .oneOff,
        oneOffStartAt: Date? = nil,
        loopIntervalMinutes: Int = 15,
        loopRepeatCount: Int = 0,
        pathLoopTimings: [PathLoopTiming] = [],
        pathStartDelays: [PathStartDelay] = [],
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
        self.scheduleMode = scheduleMode
        self.oneOffStartAt = oneOffStartAt
        self.loopIntervalMinutes = loopIntervalMinutes
        self.loopRepeatCount = loopRepeatCount
        self.pathLoopTimings = pathLoopTimings
        self.pathStartDelays = pathStartDelays
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
    }

    convenience init(
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
            scheduleMode: scheduleMode,
            oneOffStartAt: oneOffStartAt,
            loopIntervalMinutes: loopIntervalMinutes,
            loopRepeatCount: loopRepeatCount,
            pathLoopTimings: pathLoopTimings,
            pathStartDelays: pathStartDelays,
            assignments: assignments,
            createdAt: createdAt
        )
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.pendingGracefulCycleStop = pendingGracefulCycleStop
        self.reportCyclesCompleted = reportCyclesCompleted
        self.completionKind = completionKind
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
    }

    fileprivate func mutateCompiledPlan(_ plan: MissionControlPlan?) {
        compiledPlan = plan
    }

    fileprivate func setSessionPhase(_ phase: MissionRunSessionPhase) {
        sessionPhase = phase
    }

    fileprivate func clearEvents() {
        events.removeAll()
    }

    fileprivate func setOneOffDeferredExecution(_ value: MissionOneOffDeferredExecution?) {
        oneOffDeferredExecution = value
    }

    fileprivate func mutateCycleIntermission(forPathID pathID: UUID, value: MissionCycleIntermission?) {
        if let value {
            cycleIntermissionByPathID[pathID] = value
        } else {
            cycleIntermissionByPathID.removeValue(forKey: pathID)
        }
    }

    fileprivate func clearCycleIntermission(forPathID pathID: UUID? = nil) {
        if let pathID {
            cycleIntermissionByPathID.removeValue(forKey: pathID)
        } else {
            cycleIntermissionByPathID.removeAll()
        }
    }

    fileprivate func mutatePathStartDeferral(forPathID pathID: UUID, value: MissionPathStartDeferral?) {
        if let value {
            pathStartDeferralByPathID[pathID] = value
        } else {
            pathStartDeferralByPathID.removeValue(forKey: pathID)
        }
    }

    fileprivate func clearPathStartDeferral(forPathID pathID: UUID? = nil) {
        if let pathID {
            pathStartDeferralByPathID.removeValue(forKey: pathID)
        } else {
            pathStartDeferralByPathID.removeAll()
        }
    }

    var includesSimulationVehicles: Bool {
        assignments.contains {
            guard let key = $0.attachedFleetVehicleToken else { return false }
            guard let token = FleetMissionVehicleToken(storageKey: key) else { return false }
            if case .sitl = token { return true }
            return false
        }
    }

    var repeatsAutopilotMissionCycles: Bool {
        scheduleMode == .loop || scheduleMode == .continuous
    }

    var loopDelayMinutesClamped: Int {
        min(59, max(0, loopIntervalMinutes))
    }

    var paladinTightCycleHandoff: Bool {
        repeatsAutopilotMissionCycles && (scheduleMode == .continuous || loopDelayMinutesClamped == 0)
    }

    func oneOffScheduledTimeTooFarInPast(referenceNow: Date) -> Bool {
        guard let t = oneOffStartAt else { return false }
        return t.timeIntervalSince(referenceNow) < -Self.oneOffScheduleTimeTolerance
    }

    func loopDelayMinutes(forPath pathId: UUID) -> Int {
        if let t = pathLoopTimings.first(where: { $0.pathId == pathId }) {
            return min(59, max(0, t.intervalMinutes))
        }
        return loopDelayMinutesClamped
    }

    func startDelayMinutes(forPath pathId: UUID) -> Int {
        if let t = pathStartDelays.first(where: { $0.pathId == pathId }) {
            return min(59, max(0, t.startDelayMinutes))
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
        sessionPhase = .staging
    }

    func appendEvent(_ event: MissionRunEvent) {
        events.append(event)
    }

    func setMissionCycleCount(_ count: Int) {
        cyclesCompleted = max(0, count)
    }

}

@MainActor
final class MissionRunSystems {
    let lifecycle: MissionRunLifecycleSubsystem
    let logging: MissionRunLoggingSubsystem
    let commands: MissionRunCommandSubsystem
    let planner: MissionRunPlannerSubsystem
    let projections: MissionRunProjectionsSubsystem
    let executor: MissionRunExecutionSubsystem
    let scheduling: MissionRunSchedulingSubsystem

    init(
        lifecycle: MissionRunLifecycleSubsystem,
        logging: MissionRunLoggingSubsystem,
        commands: MissionRunCommandSubsystem,
        planner: MissionRunPlannerSubsystem,
        projections: MissionRunProjectionsSubsystem,
        executor: MissionRunExecutionSubsystem,
        scheduling: MissionRunSchedulingSubsystem
    ) {
        self.lifecycle = lifecycle
        self.logging = logging
        self.commands = commands
        self.planner = planner
        self.projections = projections
        self.executor = executor
        self.scheduling = scheduling
    }
}

@MainActor
final class MissionRunPlannerSubsystem {
    typealias PlanningCallback = @MainActor (
        _ run: MissionRunEnvironment,
        _ mission: Mission,
        _ fleetVehicles: [MissionPickableFleetVehicle],
        _ plan: MissionControlPlan
    ) -> MissionControlPlan
    typealias MutationProposalCallback = @MainActor (
        _ run: MissionRunEnvironment,
        _ mission: Mission,
        _ fleetVehicles: [MissionPickableFleetVehicle],
        _ mutation: MissionControlPlanMutation
    ) -> MissionControlPlanMutation?
    typealias MutationCommitCallback = @MainActor (
        _ run: MissionRunEnvironment,
        _ mission: Mission,
        _ fleetVehicles: [MissionPickableFleetVehicle],
        _ result: MissionControlPlanChangeResult
    ) -> Void
    typealias AbortPlanCallback = @MainActor (_ run: MissionRunEnvironment, _ plan: MissionRunAbortPlan) -> MissionRunAbortPlan

    weak var environment: MissionRunEnvironment?
    private var planningCallbacksByKey: [String: PlanningCallback] = [:]
    private var mutationProposalCallbacksByKey: [String: MutationProposalCallback] = [:]
    private var mutationCommitCallbacksByKey: [String: MutationCommitCallback] = [:]
    private var abortPlanCallbacksByKey: [String: AbortPlanCallback] = [:]
    private(set) var revision: Int = 0
    private(set) var revisionHistory: [MissionControlPlanRevisionRecord] = []
    /// Most recent abort plan from ``buildAbortPlan(trigger:)`` (consult before wiring execution).
    private(set) var lastBuiltAbortPlan: MissionRunAbortPlan?

    func registerPlanningCallback(key: String, callback: @escaping PlanningCallback) {
        planningCallbacksByKey[key] = callback
    }

    func unregisterPlanningCallback(key: String) {
        planningCallbacksByKey.removeValue(forKey: key)
    }

    func clearPlanningCallbacks() {
        planningCallbacksByKey.removeAll()
    }

    func registerMutationProposalCallback(key: String, callback: @escaping MutationProposalCallback) {
        mutationProposalCallbacksByKey[key] = callback
    }

    func unregisterMutationProposalCallback(key: String) {
        mutationProposalCallbacksByKey.removeValue(forKey: key)
    }

    func registerMutationCommitCallback(key: String, callback: @escaping MutationCommitCallback) {
        mutationCommitCallbacksByKey[key] = callback
    }

    func unregisterMutationCommitCallback(key: String) {
        mutationCommitCallbacksByKey.removeValue(forKey: key)
    }

    func clearMutationCallbacks() {
        mutationProposalCallbacksByKey.removeAll()
        mutationCommitCallbacksByKey.removeAll()
    }

    func registerAbortPlanCallback(key: String, callback: @escaping AbortPlanCallback) {
        abortPlanCallbacksByKey[key] = callback
    }

    func unregisterAbortPlanCallback(key: String) {
        abortPlanCallbacksByKey.removeValue(forKey: key)
    }

    /// Builds per-assignment abort commands from run default + per-slot overrides; runs ``MissionRunAbortPlanningAssistant`` hooks.
    func buildAbortPlan(trigger: MissionRunAbortTrigger) -> MissionRunAbortPlan {
        guard let environment else {
            let plan = MissionRunAbortPlan(builtAt: Date(), trigger: trigger, entries: [])
            lastBuiltAbortPlan = plan
            return plan
        }
        var entries: [MissionRunAbortPlanEntry] = []
        for assignment in environment.assignments {
            let resolved = assignment.policies.abort ?? environment.policies.abort
            let baseCommand = Self.fleetVehicleCommand(for: resolved)
            let issued: MissionRunIssuedCommand?
            if let baseCommand,
               let tokenKey = assignment.attachedFleetVehicleToken,
               FleetMissionVehicleToken(storageKey: tokenKey) != nil {
                issued = MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    command: baseCommand,
                    issuer: .missionControl,
                    issuerKey: MissionRunCommandIssuerKey.plannerAbort,
                    category: .paladin
                )
            } else {
                issued = nil
            }
            entries.append(
                MissionRunAbortPlanEntry(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    resolvedPolicy: resolved,
                    issuedCommand: issued
                )
            )
        }
        var plan = MissionRunAbortPlan(builtAt: Date(), trigger: trigger, entries: entries)
        for key in abortPlanCallbacksByKey.keys.sorted() {
            guard let callback = abortPlanCallbacksByKey[key] else { continue }
            plan = callback(environment, plan)
        }
        lastBuiltAbortPlan = plan
        return plan
    }

    private static func fleetVehicleCommand(for policy: MissionRunAbortPolicy) -> FleetVehicleCommand? {
        switch policy {
        case .returnToLaunch: return .returnToLaunch
        case .holdPosition: return .holdPosition
        case .land: return .land
        case .none: return nil
        }
    }

    func buildPlan(
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) -> MissionControlPlan? {
        guard let environment else { return nil }
        var plan = MissionControlPlanCompiler.compile(
            run: environment,
            mission: mission,
            fleetVehicles: fleetVehicles
        )
        for key in planningCallbacksByKey.keys.sorted() {
            guard let callback = planningCallbacksByKey[key] else { continue }
            plan = callback(environment, mission, fleetVehicles, plan)
        }
        return plan
    }

    @discardableResult
    func compileInitialPlan(
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        source: String = "missionControl.plan.initial",
        reason: String? = nil
    ) -> MissionControlPlanChangeResult? {
        guard let environment, let plan = buildPlan(mission: mission, fleetVehicles: fleetVehicles) else {
            return nil
        }
        let previousPlan = environment.compiledPlan
        environment.mutateCompiledPlan(plan)
        revision += 1
        let changeSet = Self.makeChangeSet(previousPlan: previousPlan, currentPlan: plan)
        let result = MissionControlPlanChangeResult(
            revision: revision,
            plan: plan,
            changeSet: changeSet,
            source: source,
            reason: reason
        )
        appendRevisionRecord(
            revision: revision,
            source: source,
            reason: reason,
            changeSet: changeSet
        )
        for key in mutationCommitCallbacksByKey.keys.sorted() {
            mutationCommitCallbacksByKey[key]?(environment, mission, fleetVehicles, result)
        }
        return result
    }

    @discardableResult
    func applyMutation(
        _ mutation: MissionControlPlanMutation,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        source: String = "missionControl.plan.mutation",
        reason: String? = nil
    ) -> MissionControlPlanChangeResult? {
        guard let environment else { return nil }
        guard let vetted = vetMutation(mutation, mission: mission, fleetVehicles: fleetVehicles) else { return nil }
        guard apply(vetted, on: environment) else { return nil }
        return compileInitialPlan(
            mission: mission,
            fleetVehicles: fleetVehicles,
            source: source,
            reason: reason
        )
    }

    @discardableResult
    func applyMutations(
        _ mutations: [MissionControlPlanMutation],
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        source: String = "missionControl.plan.batchMutation",
        reason: String? = nil
    ) -> MissionControlPlanChangeResult? {
        guard let environment else { return nil }
        let originalScheduleMode = environment.scheduleMode
        let originalLoopIntervalMinutes = environment.loopIntervalMinutes
        let originalLoopRepeatCount = environment.loopRepeatCount
        let originalPathStartDelays = environment.pathStartDelays
        let originalAssignments = environment.assignments

        for mutation in mutations {
            guard let vetted = vetMutation(mutation, mission: mission, fleetVehicles: fleetVehicles),
                  apply(vetted, on: environment)
            else {
                environment.scheduleMode = originalScheduleMode
                environment.loopIntervalMinutes = originalLoopIntervalMinutes
                environment.loopRepeatCount = originalLoopRepeatCount
                environment.pathStartDelays = originalPathStartDelays
                environment.assignments = originalAssignments
                return nil
            }
        }
        return compileInitialPlan(
            mission: mission,
            fleetVehicles: fleetVehicles,
            source: source,
            reason: reason
        )
    }

    func clearCompiledPlan() {
        environment?.mutateCompiledPlan(nil)
        revision = 0
        revisionHistory.removeAll()
    }

    func buildDronePathMission(
        mission: Mission,
        pathId: UUID
    ) -> (assignment: MissionRunAssignment, items: [Mavsdk.Mission.MissionItem])? {
        guard let environment else { return nil }
        guard let path = mission.routeMacro.paths.first(where: { $0.id == pathId && $0.enabled }),
              !path.waypoints.isEmpty
        else { return nil }
        let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
        let assignmentsForPath = environment.assignments.filter { assignment in
            if assignment.pathId == path.id { return true }
            if assignment.pathId == nil, enabledPaths.count == 1 { return true }
            return false
        }
        guard assignmentsForPath.count == 1,
              let assignment = assignmentsForPath.first,
              assignment.attachedFleetVehicleToken != nil
        else { return nil }
        let home = mission.routeMacro.home
        var items: [Mavsdk.Mission.MissionItem] = []
        if let staging = assignment.simStartOverrideCoord, let firstWP = path.waypoints.first {
            items.append(
                Utilities.mission.path.waypoint.mavItem(
                    coord: staging,
                    waypoint: firstWP,
                    home: home,
                    useWaypointHeadingForYaw: true
                )
            )
        }
        for (index, wp) in path.waypoints.enumerated() {
            let ignoreDelay = Utilities.mission.path.waypoint.shouldIgnoreClosingWaypointDelay(
                path: path,
                index: index,
                waypoint: wp
            )
            items.append(
                Utilities.mission.path.waypoint.mavItem(
                    coord: wp.coord,
                    waypoint: wp,
                    home: home,
                    useWaypointHeadingForYaw: true,
                    loiterOverrideSeconds: ignoreDelay ? 0 : nil
                )
            )
        }
        return (assignment, items)
    }

    func buildSingleDronePathMission(
        mission: Mission
    ) -> (assignment: MissionRunAssignment, items: [Mavsdk.Mission.MissionItem])? {
        let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
        guard enabledPaths.count == 1, let path = enabledPaths.first else { return nil }
        return buildDronePathMission(mission: mission, pathId: path.id)
    }

    private func vetMutation(
        _ proposed: MissionControlPlanMutation,
        mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle]
    ) -> MissionControlPlanMutation? {
        guard let environment else { return nil }
        var mutation: MissionControlPlanMutation? = proposed
        for key in mutationProposalCallbacksByKey.keys.sorted() {
            guard let current = mutation else { break }
            mutation = mutationProposalCallbacksByKey[key]?(environment, mission, fleetVehicles, current)
        }
        return mutation
    }

    private func apply(_ mutation: MissionControlPlanMutation, on environment: MissionRunEnvironment) -> Bool {
        switch mutation {
        case let .setScheduleMode(mode):
            environment.scheduleMode = mode
            return true
        case let .setLoopIntervalMinutes(minutes):
            environment.loopIntervalMinutes = min(59, max(0, minutes))
            return true
        case let .setLoopRepeatCount(count):
            environment.loopRepeatCount = max(0, count)
            return true
        case let .upsertPathStartDelay(pathID, startDelayMinutes):
            let clamped = min(59, max(0, startDelayMinutes))
            var delays = environment.pathStartDelays
            if let idx = delays.firstIndex(where: { $0.pathId == pathID }) {
                delays[idx].startDelayMinutes = clamped
            } else {
                delays.append(PathStartDelay(pathId: pathID, startDelayMinutes: clamped))
            }
            environment.pathStartDelays = delays
            return true
        case let .removePathStartDelay(pathID):
            environment.pathStartDelays.removeAll { $0.pathId == pathID }
            return true
        case let .replaceAssignmentVehicleToken(assignmentID, vehicleTokenKey):
            guard let idx = environment.assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
            environment.assignments[idx].attachedFleetVehicleToken = vehicleTokenKey
            return true
        case let .updateAssignmentPath(assignmentID, pathID):
            guard let idx = environment.assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
            environment.assignments[idx].pathId = pathID
            return true
        case let .updateAssignmentSimStartOverride(assignmentID, coordinate):
            guard let idx = environment.assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
            environment.assignments[idx].simStartOverrideCoord = coordinate
            return true
        }
    }

    private func appendRevisionRecord(
        revision: Int,
        source: String,
        reason: String?,
        changeSet: MissionControlPlanChangeSet
    ) {
        let summary = "Assignments +\(changeSet.addedAssignmentIDs.count) / -\(changeSet.removedAssignmentIDs.count) / ~\(changeSet.changedAssignmentIDs.count), paths changed: \(changeSet.changedPathIDs.count)."
        revisionHistory.append(
            MissionControlPlanRevisionRecord(
                revision: revision,
                source: source,
                reason: reason,
                summary: summary
            )
        )
    }

    private static func makeChangeSet(
        previousPlan: MissionControlPlan?,
        currentPlan: MissionControlPlan
    ) -> MissionControlPlanChangeSet {
        guard let previousPlan else {
            return MissionControlPlanChangeSet(
                previousPlan: nil,
                currentPlan: currentPlan,
                addedAssignmentIDs: currentPlan.roleTracks.map(\.assignmentID),
                removedAssignmentIDs: [],
                changedAssignmentIDs: [],
                changedPathIDs: Array(Set(currentPlan.roleTracks.compactMap(\.pathID))).sorted { $0.uuidString < $1.uuidString }
            )
        }

        let previousByAssignment = Dictionary(uniqueKeysWithValues: previousPlan.roleTracks.map { ($0.assignmentID, $0) })
        let currentByAssignment = Dictionary(uniqueKeysWithValues: currentPlan.roleTracks.map { ($0.assignmentID, $0) })
        let previousIDs = Set(previousByAssignment.keys)
        let currentIDs = Set(currentByAssignment.keys)

        let added = Array(currentIDs.subtracting(previousIDs)).sorted { $0.uuidString < $1.uuidString }
        let removed = Array(previousIDs.subtracting(currentIDs)).sorted { $0.uuidString < $1.uuidString }
        let common = previousIDs.intersection(currentIDs)
        let changed = Array(common.filter { previousByAssignment[$0] != currentByAssignment[$0] }).sorted { $0.uuidString < $1.uuidString }
        let changedPathIDs = Array(
            Set(
                changed.compactMap { currentByAssignment[$0]?.pathID ?? previousByAssignment[$0]?.pathID }
            )
        ).sorted { $0.uuidString < $1.uuidString }

        return MissionControlPlanChangeSet(
            previousPlan: previousPlan,
            currentPlan: currentPlan,
            addedAssignmentIDs: added,
            removedAssignmentIDs: removed,
            changedAssignmentIDs: changed,
            changedPathIDs: changedPathIDs
        )
    }
}

@MainActor
enum MissionRunExecutionStage: Equatable {
    case idle
    case staging
    case running
    case paused
    case teardown
    case completed
    case failed
}

struct MissionRunExecutionCursor: Equatable {
    let activePathID: UUID?
    let cycleCount: Int
}

enum MissionRunExecutionStrategy: Equatable {
    case immediate
    case safePoint
    case nextCycle
}

enum MissionRunExecutionStopMode: Equatable {
    case immediate
    case afterCycle
}

struct MissionRunExecutionContext {
    let mission: Mission?
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let missionProvider: @MainActor () -> Mission?
}

enum MissionRunExecutionEvent: Equatable {
    case missionCycleFinished(vehicleID: String)
    case deferredPathStartDue(pathID: UUID)
    case scheduledCycleRestartDue(pathID: UUID)
}

enum MissionRunExecutionDecision: Equatable {
    case noOp
    case started
    case progressed
    case paused
    case resumed
    case stopRequested(MissionRunExecutionStopMode)
    case completed(MissionRunCompletionKind)
}

@MainActor
final class MissionRunExecutionSubsystem {
    weak var environment: MissionRunEnvironment?

    private var pendingCommandBatches: [MissionRunQueuedCommandBatch] = []
    private var wallClockBatchTasks: [UUID: Task<Void, Never>] = [:]

    /// Pending batches not yet delivered (e.g. after-cycle or wall-clock); for UI/diagnostics.
    var pendingCommandBatchesSnapshot: [MissionRunQueuedCommandBatch] { pendingCommandBatches }

    var stage: MissionRunExecutionStage {
        guard let environment else { return .idle }
        switch environment.sessionPhase {
        case .draft, .compiled:
            return .idle
        case .staging:
            return .staging
        case .executing:
            return environment.status == .paused ? .paused : .running
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }

    var cursor: MissionRunExecutionCursor {
        MissionRunExecutionCursor(activePathID: nil, cycleCount: environment?.cyclesCompleted ?? 0)
    }

    @discardableResult
    func startExecution(context: MissionRunExecutionContext) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        clearCommandQueue()
        environment.captureExecutionContext(context)
        environment.systems.scheduling.cancelScheduledMissionCycle()
        environment.systems.scheduling.cancelScheduledPathMissionStarts()
        environment.systems.scheduling.clearDeferredOneOffExecution()
        environment.setMissionCycleCount(0)
        environment.systems.logging.clearState()
        environment.systems.lifecycle.markExecuting()
        if environment.startedAt == nil {
            environment.startedAt = Date()
        }
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .missionControl,
            message: "Mission execution started.",
            templateKey: PaladinLogTemplateKey.executionStarted
        )

        let staging = buildStagingPass(mission: context.mission)
        staging.events.forEach { environment.appendEvent($0) }
        for issued in staging.commands {
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl))
        }

        guard let mission = context.mission else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                message: "Mission template missing from store; cannot upload MAVLink mission.",
                templateKey: PaladinLogTemplateKey.executionMissionMissing
            )
            return .started
        }

        launchInitialMissionBatches(
            mission: mission,
            fleetLink: context.fleetLink,
            sitl: context.sitl,
            missionProvider: context.missionProvider
        )
        return .started
    }

    @discardableResult
    func pauseExecution() -> MissionRunExecutionDecision {
        environment?.systems.lifecycle.pauseRun()
        return .paused
    }

    @discardableResult
    func resumeExecution() -> MissionRunExecutionDecision {
        environment?.systems.lifecycle.resumeRun()
        return .resumed
    }

    @discardableResult
    func requestStop(mode: MissionRunExecutionStopMode) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        switch mode {
        case .immediate:
            environment.systems.scheduling.abortNow()
        case .afterCycle:
            environment.systems.scheduling.abortAfterCycle()
        }
        return .stopRequested(mode)
    }

    @discardableResult
    func handleEvent(
        _ event: MissionRunExecutionEvent,
        context: MissionRunExecutionContext
    ) -> MissionRunExecutionDecision {
        environment?.captureExecutionContext(context)
        switch event {
        case .missionCycleFinished(let vehicleID):
            return processMissionCycleFinished(vehicleID: vehicleID, context: context)
        case .deferredPathStartDue(let pathID):
            startDeferredPath(pathID: pathID, context: context)
            return .progressed
        case .scheduledCycleRestartDue(let pathID):
            restartScheduledCycle(pathID: pathID, context: context)
            return .progressed
        }
    }

    @discardableResult
    func applyPlanRevision(_ revision: Int, strategy: MissionRunExecutionStrategy) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        guard environment.systems.planner.revision >= revision else { return .noOp }
        switch strategy {
        case .immediate:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                message: "Applied plan revision \(revision) immediately."
            )
        case .safePoint:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                message: "Queued plan revision \(revision) for next safe point."
            )
        case .nextCycle:
            environment.systems.logging.appendLogEvent(
                level: .info,
                speaker: .missionControl,
                message: "Queued plan revision \(revision) for next mission cycle."
            )
        }
        return .progressed
    }

    @discardableResult
    func tick(context: MissionRunExecutionContext) -> MissionRunExecutionDecision {
        guard let environment else { return .noOp }
        environment.captureExecutionContext(context)
        guard environment.status == .running else { return .noOp }
        return .noOp
    }

    /// Drops all pending batches and cancels wall-clock waiters.
    func clearCommandQueue() {
        for (_, task) in wallClockBatchTasks {
            task.cancel()
        }
        wallClockBatchTasks.removeAll()
        pendingCommandBatches.removeAll()
    }

    /// Removes pending batches matching `tags`, optionally narrowed by `whereDispatch`.
    @discardableResult
    func cancelPendingCommandBatches(
        tags: Set<MissionRunCommandQueueTag>,
        whereDispatch matches: ((MissionRunQueuedCommandDispatch) -> Bool)? = nil
    ) -> Int {
        let removed = pendingCommandBatches.filter { batch in
            guard tags.contains(batch.tag) else { return false }
            if let matches {
                return matches(batch.dispatch)
            }
            return true
        }
        for batch in removed {
            wallClockBatchTasks[batch.id]?.cancel()
            wallClockBatchTasks.removeValue(forKey: batch.id)
        }
        let removedIDs = Set(removed.map(\.id))
        pendingCommandBatches.removeAll { removedIDs.contains($0.id) }
        return removed.count
    }

    /// - Parameter replacingTags: `nil` → cancel pending batches with the same `tag` as `batch` before enqueueing. Empty set → do not cancel.
    func enqueueCommandBatch(
        _ batch: MissionRunQueuedCommandBatch,
        context: MissionRunExecutionContext,
        replacingTags: Set<MissionRunCommandQueueTag>? = nil
    ) {
        if let explicit = replacingTags {
            if !explicit.isEmpty {
                _ = cancelPendingCommandBatches(tags: explicit)
            }
        } else {
            _ = cancelPendingCommandBatches(tags: Set([batch.tag]))
        }

        switch batch.dispatch {
        case .immediate:
            dispatchCommands(batch.commands, context: context)
        case .at(let fireDate):
            pendingCommandBatches.append(batch)
            armWallClockBatch(batchID: batch.id, fireDate: fireDate, context: context)
        case .afterMissionCycle:
            pendingCommandBatches.append(batch)
        }
    }

    /// Dispatches every `.afterMissionCycle` pending batch. Returns whether any fleet commands were sent.
    @discardableResult
    func dispatchAfterMissionCycleBatchesIfPending(context: MissionRunExecutionContext) -> Bool {
        let toDeliver = pendingCommandBatches.filter {
            if case .afterMissionCycle = $0.dispatch { return true }
            return false
        }
        guard !toDeliver.isEmpty else { return false }
        let commandCount = toDeliver.reduce(0) { $0 + $1.commands.count }
        pendingCommandBatches.removeAll { batch in
            if case .afterMissionCycle = batch.dispatch { return true }
            return false
        }
        for batch in toDeliver {
            dispatchCommands(batch.commands, context: context)
        }
        return commandCount > 0
    }

    /// Immediate abort: clear queue, cancel scheduling tasks, dispatch commands, complete run.
    func performImmediateAbort(commands: [MissionRunIssuedCommand], context: MissionRunExecutionContext) {
        guard let environment else { return }
        clearCommandQueue()
        environment.captureExecutionContext(context)
        environment.systems.scheduling.cancelAllScheduledTasks()
        dispatchCommands(commands, context: context)
        completeRun(
            context: context,
            message: "Run aborted immediately; fleet commands issued per abort plan.",
            templateKey: PaladinLogTemplateKey.runStoppedImmediate,
            kind: .operatorStoppedImmediate,
            skipImplicitReturnToLaunch: !commands.isEmpty
        )
    }

    private func armWallClockBatch(batchID: UUID, fireDate: Date, context: MissionRunExecutionContext) {
        wallClockBatchTasks[batchID]?.cancel()
        let capturedID = batchID
        let capturedFire = fireDate
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = capturedFire.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            self.deliverWallClockBatchIfStillPending(batchID: capturedID, context: context)
        }
        wallClockBatchTasks[batchID] = task
    }

    private func deliverWallClockBatchIfStillPending(batchID: UUID, context: MissionRunExecutionContext) {
        guard let idx = pendingCommandBatches.firstIndex(where: { $0.id == batchID }) else { return }
        let batch = pendingCommandBatches[idx]
        guard case .at = batch.dispatch else { return }
        pendingCommandBatches.remove(at: idx)
        wallClockBatchTasks.removeValue(forKey: batchID)
        dispatchCommands(batch.commands, context: context)
    }

    private func dispatchCommands(_ commands: [MissionRunIssuedCommand], context: MissionRunExecutionContext) {
        guard let environment else { return }
        for issued in commands {
            environment.appendEvent(
                environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl)
            )
        }
    }

    func issueReturnToLaunchForAllAssignments() {
        guard let environment, let fleetLink = environment.fleetLink, let sitl = environment.sitl else { return }
        for assignment in environment.assignments {
            guard let key = assignment.attachedFleetVehicleToken,
                  FleetMissionVehicleToken(storageKey: key) != nil
            else { continue }
            let issued = MissionRunIssuedCommand(
                assignmentID: assignment.id,
                slotName: assignment.slotName,
                vehicleTokenKey: key,
                command: .returnToLaunch,
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.runTeardown,
                category: .paladin
            )
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl))
        }
    }

    private func processMissionCycleFinished(
        vehicleID: String,
        context: MissionRunExecutionContext
    ) -> MissionRunExecutionDecision {
        guard let environment, environment.status == .running else { return .noOp }
        guard let mission = context.missionProvider(),
              let built = environment.systems.planner.buildSingleDronePathMission(mission: mission),
              let missionVehicleID = resolvedFleetStreamVehicleID(
                  assignment: built.assignment,
                  fleetLink: context.fleetLink,
                  sitl: context.sitl
              ),
              missionVehicleID == vehicleID
        else { return .noOp }

        if environment.pendingGracefulCycleStop || environment.scheduleMode == .oneOff {
            let kind: MissionRunCompletionKind = environment.pendingGracefulCycleStop ? .operatorStoppedAfterCycle : .oneOffAutopilotFinished
            let hadQueuedAbortCommands = environment.pendingGracefulCycleStop
                ? environment.systems.executor.dispatchAfterMissionCycleBatchesIfPending(context: context)
                : false
            completeRun(
                context: context,
                message: environment.pendingGracefulCycleStop
                    ? "Current mission cycle finished; graceful stop - returning to launch / home."
                    : "One-off mission cycle finished; run complete - returning to launch / home.",
                templateKey: environment.pendingGracefulCycleStop
                    ? PaladinLogTemplateKey.runGracefulAfterCycle
                    : PaladinLogTemplateKey.runOneOffFinished,
                kind: kind,
                skipImplicitReturnToLaunch: hadQueuedAbortCommands
            )
            return .completed(kind)
        }

        if environment.repeatsAutopilotMissionCycles {
            let next = environment.cyclesCompleted + 1
            environment.setMissionCycleCount(next)
            let limit = environment.loopRepeatCount
            if limit > 0, next >= limit {
                completeRun(
                    context: context,
                    message: "Loop schedule finished (\(limit) mission run(s)); returning to launch / home.",
                    templateKey: PaladinLogTemplateKey.runLoopAllRepeatsDone,
                    templateParams: ["limit": String(limit)],
                    kind: .loopCompletedAllRepeats
                )
                return .completed(.loopCompletedAllRepeats)
            }
        }

        let finishedPathID: UUID
        if let pid = built.assignment.pathId {
            finishedPathID = pid
        } else {
            let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
            guard enabledPaths.count == 1, let p = enabledPaths.first else { return .noOp }
            finishedPathID = p.id
        }

        environment.systems.scheduling.cancelScheduledMissionCycle(forPathID: finishedPathID)
        let delayMinutes: Int
        switch environment.scheduleMode {
        case .oneOff:
            return .noOp
        case .continuous:
            delayMinutes = 0
        case .loop:
            delayMinutes = environment.loopDelayMinutes(forPath: finishedPathID)
        }

        let delaySeconds = Double(delayMinutes) * 60
        let restartAt = Date().addingTimeInterval(delaySeconds)
        environment.systems.scheduling.setCycleIntermission(
            MissionCycleIntermission(restartAt: restartAt, totalDelay: delaySeconds, scheduleMode: environment.scheduleMode),
            forPathID: finishedPathID
        )
        let pathContext = environment.systems.logging.pathContextForAssignment(built.assignment.id)
        environment.systems.logging.appendLogEvent(
            level: .info,
            pathID: pathContext.0,
            pathLabel: pathContext.1,
            speaker: .paladin,
            message: delayMinutes <= 0
                ? "Mission cycle complete; starting the next cycle immediately."
                : "Mission cycle complete; next cycle in \(delayMinutes) minute(s) (loop).",
            templateKey: delayMinutes <= 0 ? PaladinLogTemplateKey.scheduleContinuousRestart : PaladinLogTemplateKey.scheduleLoopNextIn,
            templateParams: delayMinutes <= 0 ? [:] : ["minutes": String(delayMinutes)]
        )
        environment.systems.scheduling.armMissionCycleRestartTask(
            pathID: finishedPathID,
            restartAt: restartAt,
            onRestartNow: { [weak self] in
                guard let self else { return }
                _ = self.handleEvent(
                    .scheduledCycleRestartDue(pathID: finishedPathID),
                    context: context
                )
            }
        )
        return .progressed
    }

    private func restartScheduledCycle(pathID: UUID, context: MissionRunExecutionContext) {
        guard let environment else { return }
        environment.systems.scheduling.registerCycleRestartTask(nil, forPathID: pathID)
        environment.systems.scheduling.clearMissionCycleIntermission(forPathID: pathID)
        guard environment.status == .running else { return }
        guard let mission = context.missionProvider() else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .paladin,
                message: "Scheduled mission cycle skipped - mission template not found in store.",
                templateKey: PaladinLogTemplateKey.scheduleSkipNoMission
            )
            return
        }
        startPathExecution(pathID: pathID, mission: mission, context: context)
    }

    private func startDeferredPath(pathID: UUID, context: MissionRunExecutionContext) {
        guard let environment else { return }
        environment.systems.scheduling.registerDeferredPathStartTask(nil, forPathID: pathID)
        environment.systems.scheduling.clearMissionPathStartDeferral(forPathID: pathID)
        guard environment.status == .running else { return }
        guard let mission = context.missionProvider() else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .paladin,
                message: "Deferred path mission start skipped - mission template not found in store.",
                templateKey: PaladinLogTemplateKey.scheduleSkipNoMission
            )
            return
        }
        startPathExecution(pathID: pathID, mission: mission, context: context)
    }

    private func launchInitialMissionBatches(
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        missionProvider: @escaping @MainActor () -> Mission?
    ) {
        guard let environment else { return }
        let orderedEnabled = mission.routeMacro.paths.filter(\.enabled)
        struct BuildEntry { let pathId: UUID; let assignment: MissionRunAssignment }
        let buildable: [BuildEntry] = orderedEnabled.compactMap { path in
            guard let built = environment.systems.planner.buildDronePathMission(mission: mission, pathId: path.id) else { return nil }
            return BuildEntry(pathId: path.id, assignment: built.assignment)
        }
        if buildable.isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .paladin,
                message: "MAVLink mission not started (need enabled path(es) with assigned vehicle(s) and waypoints).",
                templateKey: PaladinLogTemplateKey.missionNotStarted
            )
            return
        }
        for entry in buildable {
            let mins = environment.startDelayMinutes(forPath: entry.pathId)
            guard mins > 0 else {
                startPathExecution(pathID: entry.pathId, mission: mission, context: .init(mission: mission, fleetLink: fleetLink, sitl: sitl, missionProvider: missionProvider))
                continue
            }
            let delaySeconds = Double(mins) * 60
            let startAt = Date().addingTimeInterval(delaySeconds)
            environment.systems.scheduling.setPathStartDeferral(
                MissionPathStartDeferral(startAt: startAt, totalDelay: delaySeconds),
                forPathID: entry.pathId
            )
            let pathContext = environment.systems.logging.pathContextForAssignment(entry.assignment.id)
            environment.systems.logging.appendLogEvent(
                level: .info,
                pathID: pathContext.0,
                pathLabel: pathContext.1,
                speaker: .paladin,
                message: "MAVLink mission start for this path deferred \(mins) minute(s).",
                templateKey: PaladinLogTemplateKey.schedulePathMissionStartDeferred,
                templateParams: ["minutes": String(mins)]
            )
            environment.systems.scheduling.armPathMissionStartTask(
                pathID: entry.pathId,
                startAt: startAt,
                onStartNow: { [weak self] in
                    guard let self else { return }
                    _ = self.handleEvent(
                        .deferredPathStartDue(pathID: entry.pathId),
                        context: .init(mission: mission, fleetLink: fleetLink, sitl: sitl, missionProvider: missionProvider)
                    )
                }
            )
        }
    }

    private func startPathExecution(pathID: UUID, mission: Mission, context: MissionRunExecutionContext) {
        guard let environment, environment.sessionPhase == .executing else { return }
        let pass = buildPrimaryMissionPass(mission: mission, pathId: pathID)
        pass.events.forEach { environment.appendEvent($0) }
        for issued in pass.commands {
            environment.appendEvent(environment.systems.commands.dispatchCommand(issued, fleetLink: context.fleetLink, sitl: context.sitl))
        }
    }

    private func buildStagingPass(mission: Mission?) -> MissionRunPassResult {
        guard let environment else { return MissionRunPassResult(events: [], commands: []) }
        var events: [MissionRunEvent] = []
        var commands: [MissionRunIssuedCommand] = []
        events.append(
            MissionRunEvent(
                level: .info,
                message: "Mission Control staging pass started.",
                templateKey: PaladinLogTemplateKey.stagingPassStarted
            )
        )
        let skipRelocate = (mission.flatMap { environment.systems.planner.buildSingleDronePathMission(mission: $0) } != nil)
        for assignment in environment.assignments {
            let slot = assignment.slotName
            let pc = MissionControlPathTagName.pathContext(for: assignment, mission: mission)
            let pathID = pc?.id
            let pathLabel = pc?.label
            guard let tokenKey = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: tokenKey)
            else {
                events.append(
                    MissionRunEvent(
                        level: .warning,
                        pathID: pathID,
                        pathLabel: pathLabel,
                        speaker: .missionControl,
                        message: "No fleet vehicle token; skipping staging.",
                        templateKey: PaladinLogTemplateKey.stagingNoToken
                    )
                )
                continue
            }
            switch token {
            case .sitl:
                if let coord = assignment.simStartOverrideCoord {
                    if !skipRelocate {
                        commands.append(
                            MissionRunIssuedCommand(
                                assignmentID: assignment.id,
                                slotName: slot,
                                vehicleTokenKey: tokenKey,
                                command: .gotoCoordinate(coord, relativeAltitudeM: 20, yawDeg: 0),
                                issuer: .missionControl,
                                issuerKey: MissionRunCommandIssuerKey.staging,
                                category: .paladin
                            )
                        )
                    } else {
                        events.append(
                            MissionRunEvent(
                                level: .info,
                                pathID: pathID,
                                pathLabel: pathLabel,
                                speaker: .missionControl,
                                message: "SIM staging location folded into MAVLink mission (no separate goto).",
                                templateKey: PaladinLogTemplateKey.stagingSimFoldedMission
                            )
                        )
                    }
                    events.append(
                        MissionRunEvent(
                            level: .info,
                            pathID: pathID,
                            pathLabel: pathLabel,
                            speaker: .missionControl,
                            message: String(format: "SIM staging target set to %.6f, %.6f.", coord.lat, coord.lon),
                            templateKey: PaladinLogTemplateKey.stagingSimTarget,
                            templateParams: [
                                "lat": String(format: "%.6f", coord.lat),
                                "lon": String(format: "%.6f", coord.lon),
                            ]
                        )
                    )
                } else {
                    events.append(
                        MissionRunEvent(
                            level: .warning,
                            pathID: pathID,
                            pathLabel: pathLabel,
                            speaker: .missionControl,
                            message: "SIM has no staging override; default spawn position will be used.",
                            templateKey: PaladinLogTemplateKey.stagingSimNoOverride
                        )
                    )
                }
            case .live:
                events.append(
                    MissionRunEvent(
                        level: .info,
                        pathID: pathID,
                        pathLabel: pathLabel,
                        speaker: .missionControl,
                        message: "Live vehicle staging is telemetry-driven (read-only).",
                        templateKey: PaladinLogTemplateKey.stagingLiveReadonly
                    )
                )
            }
        }
        events.append(
            MissionRunEvent(
                level: .info,
                message: "Mission Control staging pass complete (\(environment.assignments.count) slot(s) evaluated).",
                templateKey: PaladinLogTemplateKey.stagingPassComplete,
                templateParams: ["slotCount": String(environment.assignments.count)]
            )
        )
        return MissionRunPassResult(events: events, commands: commands)
    }

    private func buildPrimaryMissionPass(mission: Mission, pathId: UUID? = nil) -> MissionRunPassResult {
        guard let environment else { return MissionRunPassResult(events: [], commands: []) }
        var events: [MissionRunEvent] = []
        var commands: [MissionRunIssuedCommand] = []
        let resolvedPathId: UUID? = {
            if let pathId { return pathId }
            let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
            return enabledPaths.count == 1 ? enabledPaths.first?.id : nil
        }()
        guard let pid = resolvedPathId,
              let built = environment.systems.planner.buildDronePathMission(mission: mission, pathId: pid),
              let tokenKey = built.assignment.attachedFleetVehicleToken
        else {
            events.append(
                MissionRunEvent(
                    level: .warning,
                    speaker: .missionControl,
                    message: "MAVLink mission not started (need one enabled path, one assigned vehicle, >=1 waypoint).",
                    templateKey: PaladinLogTemplateKey.missionNotStarted
                )
            )
            return MissionRunPassResult(events: events, commands: commands)
        }
        let pc = MissionControlPathTagName.pathContext(for: built.assignment, mission: mission)
        events.append(
            MissionRunEvent(
                level: .info,
                pathID: pc?.id,
                pathLabel: pc?.label,
                speaker: .missionControl,
                message: "Executing MAVLink mission for \"\(built.assignment.slotName)\" (\(built.items.count) item(s)).",
                templateKey: PaladinLogTemplateKey.missionExecuting,
                templateParams: ["slot": built.assignment.slotName, "itemCount": String(built.items.count)]
            )
        )
        commands.append(
            MissionRunIssuedCommand(
                assignmentID: built.assignment.id,
                slotName: built.assignment.slotName,
                vehicleTokenKey: tokenKey,
                command: .uploadAndStartMission(items: built.items),
                issuer: .missionControl,
                issuerKey: MissionRunCommandIssuerKey.missionExecute,
                category: .paladin
            )
        )
        return MissionRunPassResult(events: events, commands: commands)
    }

    private func completeRun(
        context: MissionRunExecutionContext,
        message: String,
        templateKey: String?,
        templateParams: [String: String] = [:],
        kind: MissionRunCompletionKind,
        skipImplicitReturnToLaunch: Bool = false
    ) {
        guard let environment else { return }
        environment.systems.scheduling.cancelAllScheduledTasks()
        environment.systems.scheduling.clearDeferredOneOffExecution()
        var cycleSnap = environment.cyclesCompleted
        if kind == .oneOffAutopilotFinished {
            cycleSnap = max(1, cycleSnap)
        }
        environment.setMissionCycleCount(0)
        environment.status = .completed
        environment.completedAt = Date()
        environment.pendingGracefulCycleStop = false
        environment.reportCyclesCompleted = cycleSnap
        environment.completionKind = kind
        environment.setSessionPhase(.completed)
        environment.systems.logging.appendLogEvent(
            level: .info,
            speaker: .paladin,
            message: message,
            templateKey: templateKey,
            templateParams: templateParams
        )
        if !skipImplicitReturnToLaunch {
            issueReturnToLaunchForAllAssignments()
        }
        UserNotificationService.shared.notifyPaladinRunCompleted(
            runID: environment.id,
            missionName: environment.missionName,
            summary: message
        )
    }
}

@MainActor
final class MissionRunProjectionsSubsystem {
    weak var environment: MissionRunEnvironment?

    /// Temporary projection for MC-R path progress UI.
    /// TODO: Expand to multi-path / multi-vehicle progress projections.
    func mavlinkMissionProgressContext(
        mission: Mission
    ) -> (path: RoutePath, missionItemCount: Int)? {
        guard let environment,
              let (assignment, items) = environment.systems.planner.buildSingleDronePathMission(mission: mission)
        else {
            return nil
        }
        let path: RoutePath?
        if let pid = assignment.pathId {
            path = mission.routeMacro.paths.first { $0.id == pid }
        } else {
            let enabledPaths = mission.routeMacro.paths.filter(\.enabled)
            path = enabledPaths.count == 1 ? enabledPaths.first : nil
        }
        guard let path else { return nil }
        return (path, items.count)
    }
}

@MainActor
final class MissionRunSchedulingSubsystem {
    weak var environment: MissionRunEnvironment?
    private var cycleRestartTasks: [UUID: Task<Void, Never>] = [:]
    private var deferredPathStartTasks: [UUID: Task<Void, Never>] = [:]
    private var deferredOneOffStartTask: Task<Void, Never>?

    /// Operator intent: abort after the current autopilot mission cycle. Queues a tagged batch (replaceable/revocable).
    func abortAfterCycle() {
        guard let environment else { return }
        _ = environment.systems.planner.buildAbortPlan(trigger: .afterCycle)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .compactMap(\.issuedCommand)
            .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
        if let ctx = environment.lastExecutionContext {
            let batch = MissionRunQueuedCommandBatch(
                tag: .abort,
                dispatch: .afterMissionCycle,
                commands: commands
            )
            environment.systems.executor.enqueueCommandBatch(batch, context: ctx)
        } else if !commands.isEmpty {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                message: "Abort-after-cycle plan built but not queued — no execution context yet (start or cycle activity first)."
            )
        }
        environment.pendingGracefulCycleStop = true
    }

    /// Operator intent: abort immediately (dispatch abort plan, complete run).
    func abortNow() {
        guard let environment else { return }
        _ = environment.systems.planner.buildAbortPlan(trigger: .now)
        let commands = (environment.systems.planner.lastBuiltAbortPlan?.entries ?? [])
            .compactMap(\.issuedCommand)
            .map { $0.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator) }
        guard let ctx = environment.lastExecutionContext else {
            environment.systems.logging.appendLogEvent(
                level: .warning,
                speaker: .missionControl,
                message: "Abort now skipped — no execution context (fleet session not captured)."
            )
            return
        }
        environment.systems.executor.performImmediateAbort(commands: commands, context: ctx)
    }

    /// Clears graceful abort-after-cycle intent and removes the matching queued batch (if any).
    func revokeAbortAfterCycle() {
        guard let environment else { return }
        environment.pendingGracefulCycleStop = false
        _ = environment.systems.executor.cancelPendingCommandBatches(
            tags: [.abort],
            whereDispatch: {
                if case .afterMissionCycle = $0 { return true }
                return false
            }
        )
    }

    func setDeferredOneOffExecution(_ value: MissionOneOffDeferredExecution?) {
        environment?.setOneOffDeferredExecution(value)
    }

    func setCycleIntermission(_ value: MissionCycleIntermission?, forPathID pathID: UUID) {
        guard let environment else { return }
        environment.mutateCycleIntermission(forPathID: pathID, value: value)
    }

    func clearMissionCycleIntermission(forPathID pathID: UUID? = nil) {
        guard let environment else { return }
        environment.clearCycleIntermission(forPathID: pathID)
    }

    func setPathStartDeferral(_ value: MissionPathStartDeferral?, forPathID pathID: UUID) {
        guard let environment else { return }
        environment.mutatePathStartDeferral(forPathID: pathID, value: value)
    }

    func clearMissionPathStartDeferral(forPathID pathID: UUID? = nil) {
        guard let environment else { return }
        environment.clearPathStartDeferral(forPathID: pathID)
    }

    func scheduleDeferredOneOffExecution(executeAt: Date) {
        let snapshot = MissionOneOffDeferredExecution(executeAt: executeAt, countdownStartedAt: Date())
        environment?.setOneOffDeferredExecution(snapshot)
        environment?.setSessionPhase(.staging)
    }

    func scheduleDeferredOneOffExecution(
        executeAt: Date,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        scheduleDeferredOneOffExecution(executeAt: executeAt)
        armDeferredOneOffExecutionTask(executeAt: executeAt, onExecutionReady: onExecutionReady)
    }

    func clearDeferredOneOffExecution() {
        environment?.setOneOffDeferredExecution(nil)
        registerDeferredOneOffTask(nil)
    }

    func postponeDeferredOneOffExecution(byMinutes additionalMinutes: Int) {
        guard let environment, let current = environment.oneOffDeferredExecution else { return }
        let mins = min(30, max(1, additionalMinutes))
        let executeAt = current.executeAt.addingTimeInterval(Double(mins) * 60)
        environment.setOneOffDeferredExecution(MissionOneOffDeferredExecution(executeAt: executeAt, countdownStartedAt: Date()))
        environment.oneOffStartAt = executeAt
    }

    func postponeDeferredOneOffExecutionByMinutes(
        _ additionalMinutes: Int,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        postponeDeferredOneOffExecution(byMinutes: additionalMinutes)
        guard let executeAt = environment?.oneOffDeferredExecution?.executeAt else { return }
        armDeferredOneOffExecutionTask(executeAt: executeAt, onExecutionReady: onExecutionReady)
    }

    func beginDeferredOneOffNow() {
        clearDeferredOneOffExecution()
        environment?.beginRun()
    }

    func beginDeferredOneOffImmediately() {
        beginDeferredOneOffNow()
    }

    func registerCycleRestartTask(_ task: Task<Void, Never>?, forPathID pathID: UUID) {
        cycleRestartTasks[pathID]?.cancel()
        cycleRestartTasks[pathID] = task
    }

    func cancelScheduledMissionCycle(forPathID pathID: UUID? = nil) {
        if let pathID {
            cycleRestartTasks[pathID]?.cancel()
            cycleRestartTasks.removeValue(forKey: pathID)
            clearMissionCycleIntermission(forPathID: pathID)
        } else {
            cycleRestartTasks.values.forEach { $0.cancel() }
            cycleRestartTasks.removeAll()
            clearMissionCycleIntermission()
        }
    }

    func registerDeferredPathStartTask(_ task: Task<Void, Never>?, forPathID pathID: UUID) {
        deferredPathStartTasks[pathID]?.cancel()
        deferredPathStartTasks[pathID] = task
    }

    func cancelScheduledPathMissionStarts(forPathID pathID: UUID? = nil) {
        if let pathID {
            deferredPathStartTasks[pathID]?.cancel()
            deferredPathStartTasks.removeValue(forKey: pathID)
            clearMissionPathStartDeferral(forPathID: pathID)
        } else {
            deferredPathStartTasks.values.forEach { $0.cancel() }
            deferredPathStartTasks.removeAll()
            clearMissionPathStartDeferral()
        }
    }

    func registerDeferredOneOffTask(_ task: Task<Void, Never>?) {
        deferredOneOffStartTask?.cancel()
        deferredOneOffStartTask = task
    }

    func cancelAllScheduledTasks() {
        cancelScheduledMissionCycle()
        cancelScheduledPathMissionStarts()
        deferredOneOffStartTask?.cancel()
        deferredOneOffStartTask = nil
    }

    func skipMissionPathStartDeferralForPath(pathID: UUID, onStartNow: @escaping @MainActor () -> Void) {
        guard environment?.pathStartDeferralByPathID[pathID] != nil else { return }
        cancelScheduledPathMissionStarts(forPathID: pathID)
        onStartNow()
    }

    func extendMissionPathStartDeferralForPathByMinutes(
        pathID: UUID,
        additionalMinutes: Int,
        onStartNow: @escaping @MainActor () -> Void
    ) {
        guard let environment, let def = environment.pathStartDeferralByPathID[pathID] else { return }
        let mins = min(30, max(1, additionalMinutes))
        cancelScheduledPathMissionStarts(forPathID: pathID)
        let addSec = Double(mins) * 60
        let newStart = def.startAt.addingTimeInterval(addSec)
        let newTotal = def.totalDelay + addSec
        setPathStartDeferral(MissionPathStartDeferral(startAt: newStart, totalDelay: newTotal), forPathID: pathID)
        armPathMissionStartTask(pathID: pathID, startAt: newStart, onStartNow: onStartNow)
    }

    func skipMissionCycleIntermissionForPath(pathID: UUID, onRestartNow: @escaping @MainActor () -> Void) {
        guard environment?.cycleIntermissionByPathID[pathID] != nil else { return }
        cancelScheduledMissionCycle(forPathID: pathID)
        onRestartNow()
    }

    func extendMissionCycleIntermissionForPathByMinutes(
        pathID: UUID,
        additionalMinutes: Int,
        onRestartNow: @escaping @MainActor () -> Void
    ) {
        guard let inter = environment?.cycleIntermissionByPathID[pathID] else { return }
        let mins = min(30, max(1, additionalMinutes))
        cancelScheduledMissionCycle(forPathID: pathID)
        let addSec = Double(mins) * 60
        let newRestart = inter.restartAt.addingTimeInterval(addSec)
        let newTotal = inter.totalDelay + addSec
        setCycleIntermission(
            MissionCycleIntermission(restartAt: newRestart, totalDelay: newTotal, scheduleMode: inter.scheduleMode),
            forPathID: pathID
        )
        armMissionCycleRestartTask(pathID: pathID, restartAt: newRestart, onRestartNow: onRestartNow)
    }

    func armMissionCycleRestartTask(pathID: UUID, restartAt: Date, onRestartNow: @escaping @MainActor () -> Void) {
        registerCycleRestartTask(nil, forPathID: pathID)
        let captured = restartAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = captured.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let stored = self.environment?.cycleIntermissionByPathID[pathID],
                  abs(stored.restartAt.timeIntervalSince(captured)) < 0.5
            else { return }
            onRestartNow()
        }
        registerCycleRestartTask(task, forPathID: pathID)
    }

    func armPathMissionStartTask(pathID: UUID, startAt: Date, onStartNow: @escaping @MainActor () -> Void) {
        registerDeferredPathStartTask(nil, forPathID: pathID)
        let captured = startAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = captured.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let ns = UInt64(min(Double(UInt64.max), max(1_000_000, rawNs)))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let stored = self.environment?.pathStartDeferralByPathID[pathID],
                  abs(stored.startAt.timeIntervalSince(captured)) < 0.5
            else { return }
            onStartNow()
        }
        registerDeferredPathStartTask(task, forPathID: pathID)
    }

    private func armDeferredOneOffExecutionTask(
        executeAt: Date,
        onExecutionReady: @escaping @MainActor () -> Void
    ) {
        registerDeferredOneOffTask(nil)
        let captured = executeAt
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let remaining = captured.timeIntervalSince(Date())
                if remaining <= 0.05 { break }
                let chunk = min(remaining, 3600)
                let rawNs = chunk * 1_000_000_000
                guard rawNs.isFinite, rawNs > 0 else { break }
                let clamped = min(rawNs, Double(UInt64.max))
                let ns = UInt64(max(1_000_000, clamped))
                try? await Task.sleep(nanoseconds: ns)
            }
            guard !Task.isCancelled else { return }
            guard let environment = self.environment,
                  environment.status == .running,
                  let stored = environment.oneOffDeferredExecution,
                  stored.executeAt == captured
            else { return }
            self.registerDeferredOneOffTask(nil)
            self.setDeferredOneOffExecution(nil)
            onExecutionReady()
        }
        registerDeferredOneOffTask(task)
    }
}

@MainActor
final class MissionRunLifecycleSubsystem {
    weak var environment: MissionRunEnvironment?

    func markCompiled() {
        environment?.setSessionPhase(.compiled)
    }

    func markExecuting() {
        environment?.status = .running
        environment?.setSessionPhase(.executing)
    }

    func pauseRun() {
        environment?.status = .paused
    }

    func resumeRun() {
        environment?.status = .running
    }

    func markCompleted(kind: MissionRunCompletionKind? = nil) {
        guard let environment else { return }
        environment.status = .completed
        environment.completedAt = Date()
        environment.completionKind = kind
        environment.reportCyclesCompleted = environment.cyclesCompleted
        environment.setSessionPhase(.completed)
        environment.systems.scheduling.cancelAllScheduledTasks()
    }

    func markFailed(detail: String? = nil) {
        guard let environment else { return }
        environment.status = .completed
        environment.completedAt = Date()
        environment.setSessionPhase(.failed)
        if let detail {
            environment.appendEvent(MissionRunEvent(level: .error, message: detail))
        }
        environment.systems.scheduling.cancelAllScheduledTasks()
    }

    func resetToSetup() {
        guard let environment else { return }
        environment.systems.scheduling.cancelAllScheduledTasks()
        environment.status = .setup
        environment.setSessionPhase(.draft)
        environment.pendingGracefulCycleStop = false
        environment.systems.scheduling.setDeferredOneOffExecution(nil)
        environment.startedAt = nil
        environment.completedAt = nil
        environment.reportCyclesCompleted = nil
        environment.completionKind = nil
        environment.setMissionCycleCount(0)
        environment.clearEvents()
        environment.systems.planner.clearCompiledPlan()
        environment.systems.logging.clearState()
        environment.systems.executor.clearCommandQueue()
        environment.captureExecutionContext(nil)
    }
}

@MainActor
final class MissionRunLoggingSubsystem {
    private struct VehicleVoiceSnapshot: Equatable {
        var flightMode: String
        var isArmed: Bool
        var relativeAltM: Double?
        var latitudeDeg: Double?
        var longitudeDeg: Double?
        var inAir: Bool?
        var lastTrackLogAt: Date?
        var lastTrackLoggedLat: Double?
        var lastTrackLoggedLon: Double?
        var lastAltTrendLogAt: Date?
        var lastRouteProgressLogAt: Date?
        var announcedApproachWP1: Bool
    }

    weak var environment: MissionRunEnvironment?
    private var pathContextByAssignmentID: [UUID: (pathID: UUID?, pathLabel: String?)] = [:]
    private var vehicleVoiceSnapshots: [UUID: VehicleVoiceSnapshot] = [:]

    func appendLogEvent(
        level: MissionRunEventLevel,
        pathID: UUID? = nil,
        pathLabel: String? = nil,
        speaker: MissionRunEventSpeaker = .missionControl,
        message: String,
        templateKey: String? = nil,
        templateParams: [String: String] = [:]
    ) {
        environment?.appendEvent(
            MissionRunEvent(
                level: level,
                pathID: pathID,
                pathLabel: pathLabel,
                speaker: speaker,
                message: message,
                templateKey: templateKey,
                templateParams: templateParams
            )
        )
    }

    func setPathContextFromRoleTracks(_ tracks: [MissionControlRoleTrack]) {
        var context: [UUID: (pathID: UUID?, pathLabel: String?)] = [:]
        for track in tracks {
            context[track.assignmentID] = (track.pathID, track.pathDisplayName)
        }
        pathContextByAssignmentID = context
    }

    func pathContextForAssignment(_ assignmentID: UUID) -> (UUID?, String?) {
        let ctx = pathContextByAssignmentID[assignmentID] ?? (nil, nil)
        return (ctx.pathID, ctx.pathLabel)
    }

    func clearState() {
        vehicleVoiceSnapshots.removeAll()
        pathContextByAssignmentID.removeAll()
    }

    func appendFleetMirrorLine(
        vehicleID: String,
        line: String,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment else { return }
        guard environment.status == .running || environment.status == .paused else { return }
        guard environment.sessionPhase == .executing else { return }
        guard let assignment = environment.assignments.first(where: {
            resolvedFleetStreamVehicleID(assignment: $0, fleetLink: fleetLink, sitl: sitl) == vehicleID
        }) else { return }
        let level: MissionRunEventLevel
        if line.contains("[CRITICAL]") || line.contains("[ERROR]")
            || line.contains("[EMERGENCY]") || line.contains("[ALERT]") {
            level = .error
        } else if line.contains("[WARN]") {
            level = .warning
        } else {
            level = .info
        }
        let ctx = pathContextForAssignment(assignment.id)
        let classified = PaladinFleetMirrorLineClassifier.classify(line)
        appendLogEvent(
            level: level,
            pathID: ctx.0,
            pathLabel: ctx.1,
            speaker: .vehicleSlot(assignment.slotName),
            message: classified.message,
            templateKey: classified.templateKey,
            templateParams: classified.params
        )
    }

    func ingestVehicleTelemetryNarrative(
        mission: Mission?,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment else { return }
        guard environment.status == .running || environment.status == .paused else { return }
        guard environment.sessionPhase == .executing else { return }
        for assignment in environment.assignments {
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl),
                  let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            else { continue }
            let slot = assignment.slotName
            let pathFields = pathContextForAssignment(assignment.id)
            let prev = vehicleVoiceSnapshots[assignment.id]
            var lastTrack = prev?.lastTrackLogAt
            var lastTrackLoggedLat = prev?.lastTrackLoggedLat
            var lastTrackLoggedLon = prev?.lastTrackLoggedLon
            var lastAlt = prev?.lastAltTrendLogAt
            var lastRoute = prev?.lastRouteProgressLogAt
            var announcedWP = prev?.announcedApproachWP1 ?? false
            if prev == nil {
                let mode = hub.flightMode.isEmpty ? "unknown" : hub.flightMode
                let arm = hub.isArmed ? "armed" : "disarmed"
                let alt = hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "-"
                appendLogEvent(
                    level: .info,
                    pathID: pathFields.0,
                    pathLabel: pathFields.1,
                    speaker: .vehicleSlot(slot),
                    message: "Autopilot: mode \(mode), \(arm), rel alt \(alt).",
                    templateKey: PaladinLogTemplateKey.telemetryAutopilotSnapshot,
                    templateParams: ["mode": mode, "armState": arm, "relAlt": alt]
                )
            } else if prev!.flightMode != hub.flightMode, !hub.flightMode.isEmpty {
                appendLogEvent(
                    level: .info,
                    pathID: pathFields.0,
                    pathLabel: pathFields.1,
                    speaker: .vehicleSlot(slot),
                    message: "Flight mode: \(prev!.flightMode) -> \(hub.flightMode).",
                    templateKey: PaladinLogTemplateKey.telemetryFlightModeChange,
                    templateParams: ["from": prev!.flightMode, "to": hub.flightMode]
                )
            } else if prev!.isArmed != hub.isArmed {
                appendLogEvent(
                    level: .info,
                    pathID: pathFields.0,
                    pathLabel: pathFields.1,
                    speaker: .vehicleSlot(slot),
                    message: hub.isArmed ? "Armed." : "Disarmed.",
                    templateKey: hub.isArmed ? PaladinLogTemplateKey.telemetryArmed : PaladinLogTemplateKey.telemetryDisarmed
                )
            } else if let was = prev!.inAir, let now = hub.inAir, was != now {
                appendLogEvent(
                    level: .info,
                    pathID: pathFields.0,
                    pathLabel: pathFields.1,
                    speaker: .vehicleSlot(slot),
                    message: now ? "Airborne." : "On ground (in-air flag cleared).",
                    templateKey: now ? PaladinLogTemplateKey.telemetryAirborne : PaladinLogTemplateKey.telemetryOnGround
                )
            }
            if let r = hub.relativeAltM, let prevAlt = prev?.relativeAltM {
                let delta = r - prevAlt
                let since = lastAlt.map { Date().timeIntervalSince($0) } ?? 100
                if abs(delta) >= 2.5, since >= 4 {
                    let trend = delta > 0 ? "Climbing" : "Descending"
                    appendLogEvent(
                        level: .info,
                        pathID: pathFields.0,
                        pathLabel: pathFields.1,
                        speaker: .vehicleSlot(slot),
                        message: "\(trend) - rel alt ~\(String(format: "%.1f", r)) m (delta \(String(format: "%.1f", delta)) m).",
                        templateKey: PaladinLogTemplateKey.telemetryAltTrend,
                        templateParams: ["trend": trend, "alt": String(format: "%.1f", r), "delta": String(format: "%.1f", delta)]
                    )
                    lastAlt = Date()
                }
            }
            if let lat = hub.latitudeDeg, let lon = hub.longitudeDeg {
                if lastTrackLoggedLat == nil || lastTrackLoggedLon == nil {
                    lastTrackLoggedLat = lat
                    lastTrackLoggedLon = lon
                } else if let refLat = lastTrackLoggedLat, let refLon = lastTrackLoggedLon {
                    let moved = MissionTelemetryGeo.horizontalDistanceM(lat1: refLat, lon1: refLon, lat2: lat, lon2: lon)
                    if moved >= 12 {
                        let alt = hub.relativeAltM.map { String(format: "%.1f m", $0) } ?? "-"
                        let mode = hub.flightMode.isEmpty ? "-" : hub.flightMode
                        appendLogEvent(
                            level: .info,
                            pathID: pathFields.0,
                            pathLabel: pathFields.1,
                            speaker: .vehicleSlot(slot),
                            message: "Track - \(String(format: "%.5f", lat)) deg, \(String(format: "%.5f", lon)) deg · rel alt \(alt) · \(mode).",
                            templateKey: PaladinLogTemplateKey.telemetryTrack,
                            templateParams: ["lat": String(format: "%.5f", lat), "lon": String(format: "%.5f", lon), "relAlt": alt, "mode": mode]
                        )
                        lastTrackLoggedLat = lat
                        lastTrackLoggedLon = lon
                        lastTrack = Date()
                    }
                }
            }
            if let mission,
               let wp = Self.firstMissionWaypoint(for: assignment, mission: mission),
               let lat = hub.latitudeDeg,
               let lon = hub.longitudeDeg,
               let heading = hub.headingDeg ?? hub.yawDeg {
                let dist = MissionTelemetryGeo.horizontalDistanceM(lat1: lat, lon1: lon, lat2: wp.lat, lon2: wp.lon)
                let bear = MissionTelemetryGeo.bearingDegrees(lat1: lat, lon1: lon, lat2: wp.lat, lon2: wp.lon)
                let turn = abs(MissionTelemetryGeo.angleDifferenceDeg(heading, bear))
                let sinceR = lastRoute.map { Date().timeIntervalSince($0) } ?? 100
                if !announcedWP, dist < 38 {
                    let mode = hub.flightMode.isEmpty ? "-" : hub.flightMode
                    appendLogEvent(
                        level: .info,
                        pathID: pathFields.0,
                        pathLabel: pathFields.1,
                        speaker: .vehicleSlot(slot),
                        message: "Approaching first waypoint - ~\(Int(dist)) m out, mode \(mode).",
                        templateKey: PaladinLogTemplateKey.telemetryApproachWP1,
                        templateParams: ["distance": String(Int(dist)), "mode": mode]
                    )
                    announcedWP = true
                    lastRoute = Date()
                } else if sinceR >= 12 {
                    if turn > 28, dist > 22 {
                        appendLogEvent(
                            level: .info,
                            pathID: pathFields.0,
                            pathLabel: pathFields.1,
                            speaker: .vehicleSlot(slot),
                            message: "Turning toward leg - heading ~\(Int(heading)) deg, bearing to WP1 ~\(Int(bear)) deg (~\(Int(dist)) m).",
                            templateKey: PaladinLogTemplateKey.telemetryTurningLeg,
                            templateParams: ["heading": String(Int(heading)), "bearing": String(Int(bear)), "distance": String(Int(dist))]
                        )
                        lastRoute = Date()
                    } else if dist > 45 {
                        appendLogEvent(
                            level: .info,
                            pathID: pathFields.0,
                            pathLabel: pathFields.1,
                            speaker: .vehicleSlot(slot),
                            message: "Moving toward WP1 - ~\(Int(dist)) m, aligned within ~\(Int(turn)) deg.",
                            templateKey: PaladinLogTemplateKey.telemetryMovingWP1,
                            templateParams: ["distance": String(Int(dist)), "turn": String(Int(turn))]
                        )
                        lastRoute = Date()
                    }
                }
            }
            vehicleVoiceSnapshots[assignment.id] = VehicleVoiceSnapshot(
                flightMode: hub.flightMode,
                isArmed: hub.isArmed,
                relativeAltM: hub.relativeAltM,
                latitudeDeg: hub.latitudeDeg ?? prev?.latitudeDeg,
                longitudeDeg: hub.longitudeDeg ?? prev?.longitudeDeg,
                inAir: hub.inAir ?? prev?.inAir,
                lastTrackLogAt: lastTrack,
                lastTrackLoggedLat: lastTrackLoggedLat ?? prev?.lastTrackLoggedLat,
                lastTrackLoggedLon: lastTrackLoggedLon ?? prev?.lastTrackLoggedLon,
                lastAltTrendLogAt: lastAlt,
                lastRouteProgressLogAt: lastRoute,
                announcedApproachWP1: announcedWP
            )
        }
    }

    private static func firstMissionWaypoint(for assignment: MissionRunAssignment, mission: Mission) -> RouteCoordinate? {
        if let pid = assignment.pathId,
           let path = mission.routeMacro.paths.first(where: { $0.id == pid }),
           let coord = path.waypoints.first?.coord {
            return coord
        }
        if let path = mission.routeMacro.paths.first(where: { $0.enabled }),
           let coord = path.waypoints.first?.coord {
            return coord
        }
        return mission.routeMacro.paths.first?.waypoints.first?.coord
    }
}

@MainActor
final class MissionRunCommandSubsystem {
    weak var environment: MissionRunEnvironment?

    func dispatchCommand(
        _ issued: MissionRunIssuedCommand,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) -> MissionRunEvent {
        let ctx = environment?.systems.logging.pathContextForAssignment(issued.assignmentID) ?? (nil, nil)
        guard let token = FleetMissionVehicleToken(storageKey: issued.vehicleTokenKey) else {
            return MissionRunEvent(
                level: .error,
                pathID: ctx.0,
                pathLabel: ctx.1,
                speaker: .paladin,
                message: "Invalid vehicle token for slot \(issued.slotName); command dropped.",
                templateKey: PaladinLogTemplateKey.commandInvalidToken,
                templateParams: ["slot": issued.slotName]
            )
        }
        guard let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl) else {
            return MissionRunEvent(
                level: .error,
                pathID: ctx.0,
                pathLabel: ctx.1,
                speaker: .paladin,
                message: "Vehicle unavailable for slot \(issued.slotName); command dropped.",
                templateKey: PaladinLogTemplateKey.commandVehicleUnavailable,
                templateParams: ["slot": issued.slotName]
            )
        }
        let summary = shortCommandSummary(issued.command)
        let commandID = fleetLink.executeVehicleCommand(
            vehicleID: vehicleID,
            command: issued.command,
            source: issued.fleetDispatchSourceLabel,
            category: issued.category,
            onPaladinCommandOutcome: { [weak self] outcome in
                guard let self, let environment = self.environment else { return }
                switch outcome {
                case .succeeded:
                    let ackCtx = environment.systems.logging.pathContextForAssignment(issued.assignmentID)
                    environment.systems.logging.appendLogEvent(
                        level: .info,
                        pathID: ackCtx.0,
                        pathLabel: ackCtx.1,
                        speaker: .paladin,
                        message: "Fleet acknowledged: \(summary) on \(vehicleID).",
                        templateKey: PaladinLogTemplateKey.fleetAckSuccess,
                        templateParams: [
                            "summary": summary,
                            "vehicleID": vehicleID,
                            "issuer": issued.issuer.rawValue,
                            "issuerKey": issued.issuerKey,
                        ]
                    )
                case .failed(let reason):
                    let ackCtx = environment.systems.logging.pathContextForAssignment(issued.assignmentID)
                    environment.systems.logging.appendLogEvent(
                        level: .error,
                        pathID: ackCtx.0,
                        pathLabel: ackCtx.1,
                        speaker: .paladin,
                        message: "Fleet command failed: \(summary) - \(reason)",
                        templateKey: PaladinLogTemplateKey.fleetAckFailed,
                        templateParams: [
                            "summary": summary,
                            "reason": reason,
                            "issuer": issued.issuer.rawValue,
                            "issuerKey": issued.issuerKey,
                        ]
                    )
                }
            }
        )
        if commandID != nil {
            return MissionRunEvent(
                level: .info,
                pathID: ctx.0,
                pathLabel: ctx.1,
                speaker: .paladin,
                message: "Command dispatched to \(vehicleID).",
                templateKey: PaladinLogTemplateKey.commandDispatched,
                templateParams: [
                    "vehicleID": vehicleID,
                    "issuer": issued.issuer.rawValue,
                    "issuerKey": issued.issuerKey,
                ]
            )
        }
        return MissionRunEvent(
            level: .error,
            pathID: ctx.0,
            pathLabel: ctx.1,
            speaker: .paladin,
            message: "Command not sent to \(vehicleID) (no session, blocked by authority gate, or dispatch error).",
            templateKey: PaladinLogTemplateKey.commandNotSent,
            templateParams: ["vehicleID": vehicleID]
        )
    }

    private func shortCommandSummary(_ command: FleetVehicleCommand) -> String {
        switch command {
        case .arm: return "arm"
        case .disarm: return "disarm"
        case .holdPosition: return "hold"
        case .gotoCoordinate: return "goto"
        case .uploadAndStartMission(let items): return "upload+start mission (\(items.count) item(s))"
        case .returnToLaunch: return "return to launch"
        case .land: return "land"
        case .idle: return "idle (manual)"
        case .manualControl(let manual): return "manual \(manual.intent.rawValue)"
        }
    }
}

private enum MissionTelemetryGeo {
    static func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dlon = (lon2 - lon1) * .pi / 180
        let y = sin(dlon) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dlon)
        let t = atan2(y, x) * 180 / .pi
        return (t + 360).truncatingRemainder(dividingBy: 360)
    }

    static func angleDifferenceDeg(_ a: Double, _ b: Double) -> Double {
        let d = (a - b).truncatingRemainder(dividingBy: 360)
        if d > 180 { return d - 360 }
        if d < -180 { return d + 360 }
        return d
    }

    static func horizontalDistanceM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dphi = (lat2 - lat1) * .pi / 180
        let dlam = (lon2 - lon1) * .pi / 180
        let a = sin(dphi / 2) * sin(dphi / 2) + cos(p1) * cos(p2) * sin(dlam / 2) * sin(dlam / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}

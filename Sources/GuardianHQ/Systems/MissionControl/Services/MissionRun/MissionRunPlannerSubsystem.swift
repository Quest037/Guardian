import Foundation
import Mavsdk

@MainActor
final class MissionRunPlannerSubsystem {
    struct MissionTaskSquad: Equatable {
        let primaryAssignment: MissionRunAssignment
        let primaryRosterDevice: RosterDevice
        let wingmanRosterDevices: [RosterDevice]
    }

    struct PlannedTaskSquadMission: Equatable {
        let task: MissionTask
        let squadIndex: Int
        let squad: MissionTaskSquad
        let missionItems: [Mavsdk.Mission.MissionItem]
        /// Template + run augmentations + this primary slot’s augmentation (``MissionRunGeofencePolicyResolution/squadGeofences``).
        let effectiveGeofencesForSquad: [MissionGeofence]
    }

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

    /// Builds per-assignment abort commands from ordered **abort preference chains** (assignment → task → mission).
    ///
    /// **Planner default:** for every slot with a valid fleet token, the first dispatch is always
    /// ``FleetCommandName/fleetVehicleDoMissionClear`` so the onboard MAVLink mission is torn down before RTL,
    /// move+park, loiter, or park tactics run (avoids mission auto-land fighting abort wind-down).
    ///
    /// After the core plan is built, ``registerAbortPlanCallback`` hooks run in **lexicographic key order**.
    /// Plugins that should apply a **last-write** refinement (e.g. Paladin replacing entries) should register with a key
    /// that sorts after built-in keys (e.g. `core.*` before `plugin.paladin.abortPlan`).
    func buildAbortPlan(trigger: MissionRunAbortTrigger) -> MissionRunAbortPlan {
        guard let environment else {
            let plan = MissionRunAbortPlan(builtAt: Date(), trigger: trigger, entries: [])
            lastBuiltAbortPlan = plan
            return plan
        }
        var entries: [MissionRunAbortPlanEntry] = []
        let mission = environment.template
        for assignment in environment.assignments {
            let resolvedChain: [MissionRunAbortTactic]
            let chosen: MissionRunAbortTactic?
            let tacticIssued: MissionRunIssuedCommand?
            if let mission {
                resolvedChain = MissionRunPolicyResolution.resolvedAbortPreferenceChain(
                    assignment: assignment,
                    mission: mission
                )
                (chosen, tacticIssued) = Self.optimisticAbortIssuedCommand(
                    assignment: assignment,
                    preferenceChain: resolvedChain,
                    environment: environment,
                    mission: mission
                )
            } else {
                resolvedChain = MissionRunAbortTactic.defaultMissionAbortPreferenceChain
                chosen = nil
                tacticIssued = nil
            }
            var issuedCommands: [MissionRunIssuedCommand] = []
            if let clear = Self.catalogueMissionClearCommand(forAssignment: assignment) {
                issuedCommands.append(clear)
            }
            if let tacticIssued {
                issuedCommands.append(tacticIssued)
            }
            entries.append(
                MissionRunAbortPlanEntry(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    resolvedPreferenceChain: resolvedChain,
                    chosenTactic: chosen,
                    issuedCommands: issuedCommands
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

    /// First tactic in ``preferenceChain`` the planner can bind to a fleet dispatch (optimistic).
    private static func optimisticAbortIssuedCommand(
        assignment: MissionRunAssignment,
        preferenceChain: [MissionRunAbortTactic],
        environment: MissionRunEnvironment,
        mission: Mission
    ) -> (chosen: MissionRunAbortTactic?, issued: MissionRunIssuedCommand?) {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              FleetMissionVehicleToken(storageKey: tokenKey) != nil
        else {
            return (nil, nil)
        }
        let hub = environment.abortPlanningHubTelemetry(for: assignment)
        let taskId = MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission)
        let points = environment.runtimeMissionPoints

        for tactic in preferenceChain {
            switch tactic.kind {
            case .nearestOpenMapPoint:
                guard let tid = taskId else { continue }
                let pointKind = tactic.mapPointKind ?? .rally
                guard let hub,
                      let lat = hub.latitudeDeg,
                      let lon = hub.longitudeDeg
                else { continue }
                let relAlt = hub.guardianAbortPlanningRelativeAltitudeM
                guard let params = try? MissionRunMovePointParkPlanner.buildMovePointParkRecipeParameters(
                    kind: pointKind,
                    parentTaskID: tid,
                    missionPoints: points,
                    vehicleLatitudeDeg: lat,
                    vehicleLongitudeDeg: lon,
                    currentRelativeAltitudeM: relAlt,
                    yawDeg: hub.yawDeg ?? 0
                ) else { continue }
                let issued = MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: .recipe(
                        name: FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
                        parameters: params
                    ),
                    issuer: .missionControl,
                    issuerKey: MissionRunCommandIssuerKey.plannerAbort,
                    category: .missionControl
                )
                return (tactic, issued)

            case .returnToLaunch, .loiter, .park:
                guard let dispatch = MissionRunFleetDispatch.preferentialAbortTacticDispatch(tactic.kind) else { continue }
                let issued = MissionRunIssuedCommand(
                    assignmentID: assignment.id,
                    slotName: assignment.slotName,
                    vehicleTokenKey: tokenKey,
                    dispatch: dispatch,
                    issuer: .missionControl,
                    issuerKey: MissionRunCommandIssuerKey.plannerAbort,
                    category: .missionControl
                )
                return (tactic, issued)
            }
        }
        return (nil, nil)
    }

    /// Catalogue ``fleetVehicleDoMissionClear`` for one assignment — same leading atom ``buildAbortPlan`` uses per row
    /// (and the post–reserve-swap displaced-stream clear).
    static func catalogueMissionClearCommand(
        forAssignment assignment: MissionRunAssignment,
        issuerKey: String = MissionRunCommandIssuerKey.plannerAbort
    ) -> MissionRunIssuedCommand? {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              FleetMissionVehicleToken(storageKey: tokenKey) != nil
        else {
            return nil
        }
        return MissionRunIssuedCommand(
            assignmentID: assignment.id,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: issuerKey,
            category: .missionControl
        )
    }

    /// Catalogue ``fleetVehicleDoGeofenceClear`` for one assignment (run-complete SIM cleanup passes ``MissionRunCommandIssuerKey/runCleanupGeofenceClear``).
    static func catalogueGeofenceClearCommand(
        forAssignment assignment: MissionRunAssignment,
        issuerKey: String = MissionRunCommandIssuerKey.runCleanupGeofenceClear
    ) -> MissionRunIssuedCommand? {
        guard let tokenKey = assignment.attachedFleetVehicleToken,
              FleetMissionVehicleToken(storageKey: tokenKey) != nil
        else {
            return nil
        }
        return MissionRunIssuedCommand(
            assignmentID: assignment.id,
            slotName: assignment.slotName,
            vehicleTokenKey: tokenKey,
            dispatch: .catalogue(name: .fleetVehicleDoGeofenceClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: issuerKey,
            category: .missionControl
        )
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
        let originalTaskStartDelays = environment.taskStartDelays
        let originalAssignments = environment.assignments

        for mutation in mutations {
            guard let vetted = vetMutation(mutation, mission: mission, fleetVehicles: fleetVehicles),
                  apply(vetted, on: environment)
            else {
                environment.taskStartDelays = originalTaskStartDelays
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

    func buildTaskSquadMissions(
        mission: Mission,
        taskId: UUID
    ) -> [PlannedTaskSquadMission] {
        guard let environment else { return [] }
        guard let task = mission.routeMacro.tasks.first(where: { $0.id == taskId && $0.enabled }),
              !task.waypoints.isEmpty
        else { return [] }
        let enabledTasks = mission.routeMacro.tasks.filter(\.enabled)
        let assignmentsForTask = environment.assignments.filter { assignment in
            if assignment.taskId == task.id { return true }
            if assignment.taskId == nil, enabledTasks.count == 1 { return true }
            return false
        }
        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        let primaryAssignments = assignmentsForTask.compactMap { assignment -> (MissionRunAssignment, RosterDevice)? in
            guard assignment.attachedFleetVehicleToken != nil else { return nil }
            guard let rosterDevice = rosterByID[assignment.rosterDeviceId] else { return nil }
            guard rosterDevice.slot == .primary else { return nil }
            return (assignment, rosterDevice)
        }
        let rosterOrder = Dictionary(uniqueKeysWithValues: task.rosterDeviceIds.enumerated().map { ($1, $0) })
        let orderedPrimaries = primaryAssignments.sorted { lhs, rhs in
            let li = rosterOrder[lhs.1.id] ?? Int.max
            let ri = rosterOrder[rhs.1.id] ?? Int.max
            if li != ri { return li < ri }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }
        return orderedPrimaries.enumerated().map { idx, tuple in
            let assignment = tuple.0
            let primary = tuple.1
            let squadFences = MissionRunGeofencePolicyResolution.squadGeofences(
                primaryAssignment: assignment,
                mission: mission,
                missionWideRunAugmentation: environment.policies.missionGeofenceAugmentation,
                perTaskRunAugmentationByTaskID: environment.taskGeofenceAugmentationsByTaskID
            )
            let wingmen = mission.rosterDevices.filter { rd in
                rd.slot == .wingman && rd.leaderRosterDeviceId == primary.id
            }
            var items: [Mavsdk.Mission.MissionItem] = []
            for (index, wp) in task.waypoints.enumerated() {
                let ignoreDelay = Utilities.mission.path.waypoint.shouldIgnoreClosingWaypointDelay(
                    path: task,
                    index: index,
                    waypoint: wp
                )
                items.append(
                    Utilities.mission.path.waypoint.mavItem(
                        coord: wp.coord,
                        waypoint: wp,
                        useWaypointHeadingForYaw: true,
                        loiterOverrideSeconds: ignoreDelay ? 0 : nil
                    )
                )
            }
            return PlannedTaskSquadMission(
                task: task,
                squadIndex: idx,
                squad: MissionTaskSquad(
                    primaryAssignment: assignment,
                    primaryRosterDevice: primary,
                    wingmanRosterDevices: wingmen
                ),
                missionItems: items,
                effectiveGeofencesForSquad: squadFences
            )
        }
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
        guard let final = mutation else { return nil }
        guard Self.mutationReservePoolInvariantHolds(final, environment: environment) else {
            return nil
        }
        return final
    }

    /// Rejects roster mutations that would double-bind a fleet storage key already held in a floating reserve berth, or move a bound assignment into a task whose pool already holds that key.
    private static func mutationReservePoolInvariantHolds(
        _ mutation: MissionControlPlanMutation,
        environment: MissionRunEnvironment
    ) -> Bool {
        switch mutation {
        case let .replaceAssignmentVehicleToken(_, vehicleTokenKey):
            guard let raw = vehicleTokenKey?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return true
            }
            return !environment.reservePoolContainsFleetVehicleStorageKey(raw)
        case let .updateAssignmentTask(assignmentID, taskID):
            guard let idx = environment.assignments.firstIndex(where: { $0.id == assignmentID }) else { return true }
            let tok = environment.assignments[idx].attachedFleetVehicleToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !tok.isEmpty, let newTaskID = taskID else { return true }
            let pool = environment.reservePool(forTaskID: newTaskID)
            for slot in pool.entries {
                let sk = (slot.attachedFleetVehicleToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if sk == tok { return false }
            }
            return true
        case .upsertTaskStartDelay, .removeTaskStartDelay:
            return true
        }
    }

    private func apply(_ mutation: MissionControlPlanMutation, on environment: MissionRunEnvironment) -> Bool {
        switch mutation {
        case let .upsertTaskStartDelay(taskID, startDelayValue, startDelayUnit):
            let row = TaskStartDelay(taskId: taskID, startDelayValue: startDelayValue, startDelayUnit: startDelayUnit)
            var delays = environment.taskStartDelays
            if let idx = delays.firstIndex(where: { $0.taskId == taskID }) {
                delays[idx] = row
            } else {
                delays.append(row)
            }
            environment.taskStartDelays = delays
            return true
        case let .removeTaskStartDelay(taskID):
            environment.taskStartDelays.removeAll { $0.taskId == taskID }
            return true
        case let .replaceAssignmentVehicleToken(assignmentID, vehicleTokenKey):
            environment.clearRosterSimStartPoseSnapshots(forAssignmentIDs: [assignmentID])
            guard let idx = environment.assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
            environment.assignments[idx].attachedFleetVehicleToken = vehicleTokenKey
            return true
        case let .updateAssignmentTask(assignmentID, taskID):
            environment.clearRosterSimStartPoseSnapshots(forAssignmentIDs: [assignmentID])
            guard let idx = environment.assignments.firstIndex(where: { $0.id == assignmentID }) else { return false }
            environment.assignments[idx].taskId = taskID
            return true
        }
    }

    private func appendRevisionRecord(
        revision: Int,
        source: String,
        reason: String?,
        changeSet: MissionControlPlanChangeSet
    ) {
        let summary = "Assignments +\(changeSet.addedAssignmentIDs.count) / -\(changeSet.removedAssignmentIDs.count) / ~\(changeSet.changedAssignmentIDs.count), paths changed: \(changeSet.changedTaskIDs.count)."
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
                changedTaskIDs: Array(Set(currentPlan.roleTracks.compactMap(\.taskID))).sorted { $0.uuidString < $1.uuidString }
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
        let changedTaskIDs = Array(
            Set(
                changed.compactMap { currentByAssignment[$0]?.taskID ?? previousByAssignment[$0]?.taskID }
            )
        ).sorted { $0.uuidString < $1.uuidString }

        return MissionControlPlanChangeSet(
            previousPlan: previousPlan,
            currentPlan: currentPlan,
            addedAssignmentIDs: added,
            removedAssignmentIDs: removed,
            changedAssignmentIDs: changed,
            changedTaskIDs: changedTaskIDs
        )
    }
}

extension FleetHubVehicleTelemetry {
    /// Shared by abort and complete optimistic planners (hub-relative height for move-point-park binding).
    var guardianAbortPlanningRelativeAltitudeM: Double {
        relativeAltM ?? altitudeRelativeM ?? altitudeLocalM ?? 0
    }
}

// MARK: - Log template keys (plan compile)

extension MissionRunLogTemplateKey {
    static let compileSummary = "missioncontrol.mre.compile.summary"
}


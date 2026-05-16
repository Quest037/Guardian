import Foundation

/// What **Continue** means on the MC-R assignment triage overlay after the operator has stabilized (or while end protocol is stuck).
enum MissionRunOperatorContinueAfterParkIntent: Equatable, Sendable {
    /// Resume onboard mission execution (``FleetMissionRecipeRegistrations/doContinueMissionAfterOperatorParkRecipeName``).
    case resumeMission
    /// Re-dispatch complete-policy wind-down for this roster row only.
    case retryCompleteWindDown
    /// Re-dispatch abort-policy wind-down for this roster row only.
    case retryAbortWindDown
    case unavailable(reason: String)

    var isActionable: Bool {
        switch self {
        case .unavailable: return false
        default: return true
        }
    }

    /// True for assignment-triage **Retry recovery** / **Retry abort protocol** (async fleet jolt).
    var isPolicyWindDownRetry: Bool {
        switch self {
        case .retryCompleteWindDown, .retryAbortWindDown: return true
        default: return false
        }
    }

    var operatorShortLabel: String {
        switch self {
        case .resumeMission: return "Continue mission"
        case .retryCompleteWindDown: return "Retry recovery"
        case .retryAbortWindDown: return "Retry abort protocol"
        case .unavailable: return "Continue"
        }
    }

    var operatorHelp: String {
        switch self {
        case .resumeMission:
            return "Set mission mode, arm if needed, and start mission execution on the autopilot."
        case .retryCompleteWindDown:
            return "Jolt the in-flight recovery recipe when it is waiting on operator input; otherwise clear stuck fleet work and run recovery policy again."
        case .retryAbortWindDown:
            return "Jolt the in-flight abort-protocol recipe when it is waiting on operator input; otherwise clear stuck fleet work and run abort policy again."
        case .unavailable(let reason):
            return reason
        }
    }
}

/// Resolves MC-R **Continue** from squad state, slot policy lanes, and issued wind-down markers.
@MainActor
enum MissionControlOperatorContinueAfterParkPolicy {

    static func resolve(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        mission: Mission,
        run: MissionRunEnvironment,
        fleetLink: FleetLinkService,
        vehicleID: String?
    ) -> MissionRunOperatorContinueAfterParkIntent {
        guard let taskID = resolvedTaskID(for: assignment, mission: mission) else {
            return .unavailable(reason: "No mission task is bound to this slot.")
        }

        let mergedSlot = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(
            lanes: assignment.effectiveSlotLifecycleLanes
        )
        let slot = rosterDevice?.slot ?? .primary
        let squadState = squadStateForContinueDecision(
            assignment: assignment,
            rosterDevice: rosterDevice,
            mission: mission,
            run: run
        )

        let abortIssued = run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID)
        let completeIssued = run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID)
            || run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignment.id)
        let taskState = run.taskStateByTaskID[taskID] ?? .ready

        if slot == .wingman {
            return resolveWingman(
                assignment: assignment,
                mergedSlot: mergedSlot,
                abortIssued: abortIssued,
                completeIssued: completeIssued,
                squadState: squadState
            )
        }

        if abortIssued,
           shouldRetryAbortWindDown(squadState: squadState, mergedSlot: mergedSlot, taskState: taskState) {
            return .retryAbortWindDown
        }

        if completeIssued,
           shouldRetryCompleteWindDown(squadState: squadState, mergedSlot: mergedSlot, taskState: taskState) {
            return .retryCompleteWindDown
        }

        if shouldRetryCompleteWindDown(squadState: squadState, mergedSlot: mergedSlot, taskState: taskState),
           taskState == .recovery || run.sessionPhase == .recovery {
            return .retryCompleteWindDown
        }

        if shouldRetryAbortWindDown(squadState: squadState, mergedSlot: mergedSlot, taskState: taskState),
           taskState == .aborting || run.sessionPhase == .aborting {
            return .retryAbortWindDown
        }

        if let vehicleID,
           fleetLink.mcrOperatorVehiclePhase(vehicleID: vehicleID) == .operatorParkAwaitingContinue {
            return .resumeMission
        }

        if squadState.map(resumeMissionEligibleSquadState) == true, !abortIssued, !completeIssued {
            return .resumeMission
        }

        return .unavailable(
            reason: "Continue is available after park, or when this slot is in an active end protocol."
        )
    }

    private static func resolveWingman(
        assignment: MissionRunAssignment,
        mergedSlot: MissionRunAssignmentSlotState,
        abortIssued: Bool,
        completeIssued: Bool,
        squadState: MissionSquadState?
    ) -> MissionRunOperatorContinueAfterParkIntent {
        if abortIssued,
           policyLaneSuggestsAbortRetry(mergedSlot) {
            return .retryAbortWindDown
        }
        if completeIssued || policyLaneSuggestsCompleteRetry(mergedSlot) {
            return .retryCompleteWindDown
        }
        if policyLaneSuggestsCompleteRetry(mergedSlot) {
            return .retryCompleteWindDown
        }
        if policyLaneSuggestsAbortRetry(mergedSlot) {
            return .retryAbortWindDown
        }
        _ = assignment
        _ = squadState
        return .unavailable(
            reason: "Follower vehicle — open the primary squad slot to continue the mission."
        )
    }

    private static func squadStateForContinueDecision(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        mission: Mission,
        run: MissionRunEnvironment
    ) -> MissionSquadState? {
        if rosterDevice?.slot == .primary {
            return run.squadStateByAssignmentID[assignment.id]
        }
        guard let taskID = resolvedTaskID(for: assignment, mission: mission),
              let task = mission.routeMacro.tasks.first(where: { $0.id == taskID })
        else { return nil }
        let enabledCount = mission.routeMacro.tasks.filter(\.enabled).count
        if let leaderRosterID = rosterDevice?.leaderRosterDeviceId,
           let leaderAssignment = run.assignments.first(where: { $0.rosterDeviceId == leaderRosterID }) {
            return run.squadStateByAssignmentID[leaderAssignment.id]
        }
        let primaries = MissionControlSquadUtilities.orderedPrimarySquads(
            task: task,
            assignments: run.assignments,
            rosterDevices: mission.rosterDevices,
            enabledTaskCount: enabledCount
        )
        if primaries.count == 1 {
            return run.squadStateByAssignmentID[primaries[0].assignment.id]
        }
        return nil
    }

    private static func resolvedTaskID(for assignment: MissionRunAssignment, mission: Mission) -> UUID? {
        if let tid = assignment.taskId { return tid }
        let enabled = mission.routeMacro.tasks.filter(\.enabled)
        if enabled.count == 1 { return enabled.first?.id }
        return nil
    }

    private static func shouldRetryCompleteWindDown(
        squadState: MissionSquadState?,
        mergedSlot: MissionRunAssignmentSlotState,
        taskState: MissionTaskState
    ) -> Bool {
        if policyLaneSuggestsCompleteRetry(mergedSlot) { return true }
        if squadState == .recovery { return true }
        if taskState == .recovery { return true }
        return false
    }

    private static func shouldRetryAbortWindDown(
        squadState: MissionSquadState?,
        mergedSlot: MissionRunAssignmentSlotState,
        taskState: MissionTaskState
    ) -> Bool {
        if policyLaneSuggestsAbortRetry(mergedSlot) { return true }
        if squadState == .aborting { return true }
        if taskState == .aborting { return true }
        return false
    }

    private static func policyLaneSuggestsCompleteRetry(_ merged: MissionRunAssignmentSlotState) -> Bool {
        switch merged {
        case .policyCompleting, .policyFailed: return true
        default: return false
        }
    }

    private static func policyLaneSuggestsAbortRetry(_ merged: MissionRunAssignmentSlotState) -> Bool {
        switch merged {
        case .policyAborting, .policyFailed: return true
        default: return false
        }
    }

    private static func resumeMissionEligibleSquadState(_ state: MissionSquadState) -> Bool {
        switch state {
        case .ready, .staging, .executing, .between: return true
        case .recovery, .aborting, .aborted, .completed: return false
        }
    }
}

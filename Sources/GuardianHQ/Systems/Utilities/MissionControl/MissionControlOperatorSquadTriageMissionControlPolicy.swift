import Foundation

/// MC-R task triage **squad tab** mission-control rows (park / continue / protocol retry / terminal RTL).
enum MCRLiveTaskTriageSquadMissionControlRow: Equatable, Sendable {
    /// Park (+ optional loiter) while on mission, or **Continue** when operator-held (``.paused``).
    case mission(MCRLiveTaskTriageSquadMissionRowMode)
    /// End protocol in progress: park + retry recovery.
    case recovery
    /// Abort protocol in progress: park + retry abort.
    case aborting
    /// Settled recovery complete: squad abort + return to launch.
    case completedTerminal
    /// Settled abort complete: return to launch only.
    case abortedTerminal
}

enum MCRLiveTaskTriageSquadMissionRowMode: Equatable, Sendable {
    case onMissionPark(offersLoiter: Bool)
    case pausedContinue
}

@MainActor
enum MissionControlOperatorSquadTriageMissionControlPolicy {

    static func resolvedMissionControlRow(
        run: MissionRunEnvironment,
        task: RoutePath,
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        vehicleID: String?,
        squadState: MissionSquadState,
        now: Date
    ) -> MCRLiveTaskTriageSquadMissionControlRow? {
        _ = now
        _ = mission
        guard canOfferAnyMissionControl(
            run: run,
            task: task,
            assignment: assignment,
            vehicleID: vehicleID
        ) else { return nil }

        switch squadState {
        case .recovery:
            return .recovery
        case .aborting:
            return .aborting
        case .completed:
            return .completedTerminal
        case .aborted:
            return .abortedTerminal
        case .ready, .staging, .executing, .between, .paused:
            break
        }

        guard run.sessionPhase == .executing else { return nil }
        guard !squadInActiveEndPolicyAttempt(run: run, taskID: task.id, assignmentID: assignment.id) else {
            return nil
        }

        if squadState == .paused || run.missionSquadOperatorPausedAssignmentIDs.contains(assignment.id) {
            return .mission(.pausedContinue)
        }

        if isOnMission(
            squadState: squadState,
            assignmentID: assignment.id,
            run: run,
            vehicleID: vehicleID,
            fleetLink: fleetLink
        ) {
            let offersLoiter = offersLoiterStabilize(
                assignment: assignment,
                rosterDevice: rosterDevice,
                sitl: sitl
            )
            return .mission(.onMissionPark(offersLoiter: offersLoiter))
        }

        return nil
    }

    static func canOfferAnyMissionControl(
        run: MissionRunEnvironment,
        task: RoutePath,
        assignment: MissionRunAssignment,
        vehicleID: String?
    ) -> Bool {
        guard task.enabled else { return false }
        guard run.status == .running || run.status == .paused else { return false }
        let token = (assignment.attachedFleetVehicleToken ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, vehicleID != nil else { return false }
        return true
    }

    private static func squadInActiveEndPolicyAttempt(
        run: MissionRunEnvironment,
        taskID: UUID,
        assignmentID: UUID
    ) -> Bool {
        if run.squadCompletePolicyWindDownIssuedAssignmentIDs.contains(assignmentID) { return true }
        if run.squadAbortPolicyWindDownIssuedAssignmentIDs.contains(assignmentID) { return true }
        if run.missionTaskCompleteWindDownIssuedTaskIDs.contains(taskID) { return true }
        if run.missionTaskAbortWindDownIssuedTaskIDs.contains(taskID) { return true }
        if run.pendingMissionSquadGracefulWindDownKindByAssignmentID[assignmentID] != nil { return true }
        if run.pendingMissionTaskGracefulWindDownKindByTaskID[taskID] != nil { return true }
        return false
    }

    private static func isOnMission(
        squadState: MissionSquadState,
        assignmentID: UUID,
        run: MissionRunEnvironment,
        vehicleID: String?,
        fleetLink: FleetLinkService
    ) -> Bool {
        if run.activeCycleSquadAssignmentIDs.contains(assignmentID) { return true }
        if squadState == .executing || squadState == .between { return true }
        if let vehicleID,
           fleetLink.mcrOperatorVehiclePhase(vehicleID: vehicleID) == .onMission {
            return true
        }
        return false
    }

    private static func offersLoiterStabilize(
        assignment: MissionRunAssignment,
        rosterDevice: RosterDevice?,
        sitl: SitlService
    ) -> Bool {
        let vehicleType: FleetVehicleType = {
            if let tokenKey = assignment.attachedFleetVehicleToken,
               let token = FleetMissionVehicleToken(storageKey: tokenKey),
               case .sitl(let uuid) = token,
               let inst = sitl.instances.first(where: { $0.id == uuid }) {
                return inst.preset.fleetVehicleType
            }
            return rosterDevice?.vehicleClass ?? .unknown
        }()
        return vehicleType.universalClass != .ugv
    }
}

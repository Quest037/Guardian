import Foundation

/// §4 **dispatch start:** map ``MissionRunIssuedCommand`` leaving MRE to a **commanded**-lane ``MissionRunAssignmentSlotState``
/// before §3 push/pull terminals arrive (``TaskRosterAssignmentStatesToDo.md`` §4).
///
/// Uses recipe **raw ids** only so this stays ``nonisolated`` (fleet registration types are ``@MainActor``).
enum MissionRunPolicySlotDispatchStart {

    nonisolated static func commandedSlotStateIfDispatchLeavesMRE(
        issued: MissionRunIssuedCommand,
        effectiveTaskID: UUID?,
        abortWindDownIssuedTaskIDs: Set<UUID>,
        completeWindDownIssuedTaskIDs: Set<UUID>,
        squadCompleteWindDownIssuedAssignmentIDs: Set<UUID> = [],
        sessionPhase: MissionRunSessionPhase
    ) -> MissionRunAssignmentSlotState? {
        let key = issued.issuerKey

        if let missionUpload = missionUploadCommandedStateIfNeeded(
            dispatch: issued.dispatch,
            issuerKey: key,
            sessionPhase: sessionPhase
        ) {
            return missionUpload
        }

        if let between = betweenCyclesCommandedStateIfNeeded(dispatch: issued.dispatch, issuerKey: key) {
            return between
        }

        guard isPolicyWindDownFleetDispatch(issued.dispatch) else { return nil }

        if key == MissionRunCommandIssuerKey.plannerAbort {
            return .policyAborting
        }
        if key == MissionRunCommandIssuerKey.localOperator || key == MissionRunCommandIssuerKey.completePolicyWindDown {
            guard let tid = effectiveTaskID else { return nil }
            if abortWindDownIssuedTaskIDs.contains(tid) { return .policyAborting }
            if completeWindDownIssuedTaskIDs.contains(tid) { return .policyCompleting }
            if squadCompleteWindDownIssuedAssignmentIDs.contains(issued.assignmentID) { return .policyCompleting }
            return nil
        }
        return nil
    }

    /// True when §3 push terminals are absent for this ``issued`` + outcome path, but §4 still tracks the row through fleet ack
    /// (mission upload / between-cycles) so ``applySlotDispatchOutcomeEvidence`` can sync **observed** with fleet reality.
    nonisolated static func tracksSlotLanesThroughFleetOutcome(issued: MissionRunIssuedCommand) -> Bool {
        isMissionExecuteUploadDispatchShape(dispatch: issued.dispatch, issuerKey: issued.issuerKey)
            || isBetweenCyclesOutcomeTrackingShape(dispatch: issued.dispatch, issuerKey: issued.issuerKey)
    }

    private nonisolated static func isMissionExecuteUploadDispatchShape(dispatch: MissionRunFleetDispatch, issuerKey: String) -> Bool {
        guard issuerKey == MissionRunCommandIssuerKey.missionExecute else { return false }
        guard case .recipe(let name, _) = dispatch else { return false }
        let raw = name.rawValue
        return raw == "recipe.fleet.do.mission.upload.start" || raw == "recipe.fleet.do.mission.upload.start.item"
    }

    private nonisolated static func isBetweenCyclesOutcomeTrackingShape(dispatch: MissionRunFleetDispatch, issuerKey: String) -> Bool {
        guard issuerKey == MissionRunCommandIssuerKey.missionExecute
            || issuerKey == MissionRunCommandIssuerKey.betweenCyclesFallback
        else { return false }
        return isBetweenCyclesFleetDispatchShape(dispatch)
    }

    // MARK: - Mission execute (upload)

    private nonisolated static func missionUploadCommandedStateIfNeeded(
        dispatch: MissionRunFleetDispatch,
        issuerKey: String,
        sessionPhase: MissionRunSessionPhase
    ) -> MissionRunAssignmentSlotState? {
        guard issuerKey == MissionRunCommandIssuerKey.missionExecute else { return nil }
        guard case .recipe(let name, _) = dispatch else { return nil }
        let raw = name.rawValue
        guard raw == "recipe.fleet.do.mission.upload.start" || raw == "recipe.fleet.do.mission.upload.start.item" else {
            return nil
        }
        return sessionPhase == .staging ? .staging : .executingMission
    }

    // MARK: - Between cycles (RTL / loiter / park)

    private nonisolated static func betweenCyclesCommandedStateIfNeeded(
        dispatch: MissionRunFleetDispatch,
        issuerKey: String
    ) -> MissionRunAssignmentSlotState? {
        guard issuerKey == MissionRunCommandIssuerKey.missionExecute
            || issuerKey == MissionRunCommandIssuerKey.betweenCyclesFallback
        else { return nil }
        guard isBetweenCyclesFleetDispatchShape(dispatch) else { return nil }
        return .betweenCycles
    }

    private nonisolated static func isBetweenCyclesFleetDispatchShape(_ dispatch: MissionRunFleetDispatch) -> Bool {
        switch dispatch {
        case .catalogue(let name, _):
            return name == .fleetVehicleDoLoiter || name == .fleetVehicleDoPark
        case .recipe(let name, _):
            return name.rawValue == "recipe.fleet.do.return.home"
        case .vehicleCommand:
            return false
        }
    }

    // MARK: - Abort / complete policy wind-down (same footprint as §3 push terminals + mission clear)

    private nonisolated static func isPolicyWindDownFleetDispatch(_ dispatch: MissionRunFleetDispatch) -> Bool {
        switch dispatch {
        case .catalogue(let name, _):
            return name == .fleetVehicleDoMissionClear || name == .fleetVehicleDoLoiter || name == .fleetVehicleDoPark
        case .recipe(let name, _):
            let raw = name.rawValue
            return raw == "recipe.fleet.do.return.home"
                || raw == "recipe.fleet.do.move.point.park"
                || raw == "recipe.fleet.vehicle.do.park"
        case .vehicleCommand:
            return false
        }
    }
}

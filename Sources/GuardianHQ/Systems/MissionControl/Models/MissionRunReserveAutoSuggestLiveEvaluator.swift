import Foundation

// MARK: - MC-R live scan (kept out of MissionControlSetupView for SourceKit / type-check health)

/// First matching **primary / wingman** roster aircraft on the focused task that should trigger a floating-reserve
/// **suggest** toast (policy only — no roster commit).
///
/// Lives outside ``MissionControlSetupView`` so Xcode/SourceKit does not choke on the same 7k-line file that also
/// hosts ``MissionRunDetailView`` chrome; behaviour matches the former inline loop.
enum MissionRunReserveAutoSuggestLiveEvaluator {

    @MainActor
    static func firstSuggestMatch(
        run: MissionRunEnvironment,
        mission: Mission,
        task: MissionTask,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        now: Date
    ) -> (vehicleID: String, reason: MissionRunReserveAutoSuggestReason)? {
        let tid = task.id
        if run.availableReservePoolEntries(forTaskID: tid, classCompatibleWithAssignmentId: nil).isEmpty {
            return nil
        }

        for assignment in run.assignments {
            guard run.missionControlAssignmentBelongsToTask(assignment, task: task, mission: mission) else { continue }
            guard !run.missionRunAssignmentIDsWithOperatorLiveDriveHandoff.contains(assignment.id) else { continue }
            guard assignment.hasFleetOrLegacyAssignment else { continue }
            if let rosterDevice = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }),
               rosterDevice.slot == .reserve {
                continue
            }
            guard let vehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else {
                continue
            }

            let hasReserve = !run.availableReservePoolEntries(
                forTaskID: tid,
                classCompatibleWithAssignmentId: assignment.id
            ).isEmpty
            let gating = MissionRunReserveAutoSuggestGatingSnapshot(
                runStatus: run.status,
                sessionPhase: run.sessionPhase,
                taskState: run.taskStateByTaskID[tid],
                taskAttemptState: run.taskAttemptingByTaskID[tid],
                hasClassCompatibleFloatingReserve: hasReserve
            )
            let hub = fleetLink.hubTelemetry(forVehicleID: vehicleID)
            let op = fleetLink.vehicleOperationalModel(forVehicleID: vehicleID)
            let signals = MissionRunReserveAutoSuggestSignalSnapshot(
                batteryTraffic: op.battery.trafficBand,
                telemetryAgeS: op.telemetryAgeS,
                flightModeRaw: hub?.flightMode ?? ""
            )
            let recentFail = MissionRunReserveAutoSuggestPolicy.recentFleetDispatchFailure(
                events: run.events,
                vehicleID: vehicleID,
                lookback: MissionRunReserveAutoSuggestPolicy.defaultFleetFailureLookbackSeconds,
                now: now
            )
            guard let reason = MissionRunReserveAutoSuggestPolicy.firstSuggestReason(
                gating: gating,
                signals: signals,
                recentFleetDispatchFailure: recentFail
            ) else { continue }

            return (vehicleID, reason)
        }
        return nil
    }
}

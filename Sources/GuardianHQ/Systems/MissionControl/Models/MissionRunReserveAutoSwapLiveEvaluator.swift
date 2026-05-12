import Foundation

/// One **autonomous** reserve auto-swap opportunity: a roster vacancy in distress, exactly **one** swap candidate (pool or fixed), and a distress reason.
struct MissionRunReserveAutoSwapLiveMatch: Equatable {
    let vacancyAssignment: MissionRunAssignment
    let loneCandidate: MissionRunReserveSwapCandidate
    let distressVehicleID: String
    let reason: MissionRunReserveAutoSuggestReason
}

/// MC-R scan for **autonomous** reserve swap-in when enumeration yields a **unique** candidate (pool or fixed template reserve).
///
/// Requires ``MissionRunEngagementDisposition/autonomous`` for ``MissionRunEngagementAction/swapInReserve`` and the same
/// mid-mission lifecycle slice as suggest toasts (``MissionRunReserveAutoSuggestPolicy/gatingAllowsReserveDistressAutomationCore``).
/// Distress signals reuse ``MissionRunReserveAutoSuggestPolicy/firstDistressSignalReason`` on the **vacancy** aircraft.
enum MissionRunReserveAutoSwapLiveEvaluator {

    @MainActor
    static func firstMatch(
        run: MissionRunEnvironment,
        mission: Mission,
        task: MissionTask,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        now: Date
    ) -> MissionRunReserveAutoSwapLiveMatch? {
        guard run.resolvedEngagementDisposition(for: .swapInReserve) == .autonomous else { return nil }
        let tid = task.id
        for assignment in run.assignments {
            guard run.missionControlAssignmentBelongsToTask(assignment, task: task, mission: mission) else { continue }
            guard assignment.hasFleetOrLegacyAssignment else { continue }
            if let rosterDevice = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId }),
               rosterDevice.slot == .reserve {
                continue
            }
            guard let distressVehicleID = resolvedFleetStreamVehicleID(assignment: assignment, fleetLink: fleetLink, sitl: sitl) else {
                continue
            }
            let candidates = run.enumerateReserveSwapCandidates(
                vacancyAssignmentID: assignment.id,
                taskID: tid,
                ordering: .fixedRosterReservesFirst
            )
            guard candidates.count == 1, let lone = candidates.first else { continue }

            let core = MissionRunReserveAutoSuggestPolicy.gatingAllowsReserveDistressAutomationCore(
                runStatus: run.status,
                sessionPhase: run.sessionPhase,
                taskState: run.taskStateByTaskID[tid],
                taskAttemptState: run.taskAttemptingByTaskID[tid]
            )
            guard core else { continue }

            let hub = fleetLink.hubTelemetry(forVehicleID: distressVehicleID)
            let op = fleetLink.vehicleOperationalModel(forVehicleID: distressVehicleID)
            let signals = MissionRunReserveAutoSuggestSignalSnapshot(
                batteryTraffic: op.battery.trafficBand,
                telemetryAgeS: op.telemetryAgeS,
                flightModeRaw: hub?.flightMode ?? ""
            )
            let recentFail = MissionRunReserveAutoSuggestPolicy.recentFleetDispatchFailure(
                events: run.events,
                vehicleID: distressVehicleID,
                lookback: MissionRunReserveAutoSuggestPolicy.defaultFleetFailureLookbackSeconds,
                now: now
            )
            guard let reason = MissionRunReserveAutoSuggestPolicy.firstDistressSignalReason(
                signals: signals,
                recentFleetDispatchFailure: recentFail
            ) else { continue }

            return MissionRunReserveAutoSwapLiveMatch(
                vacancyAssignment: assignment,
                loneCandidate: lone,
                distressVehicleID: distressVehicleID,
                reason: reason
            )
        }
        return nil
    }
}

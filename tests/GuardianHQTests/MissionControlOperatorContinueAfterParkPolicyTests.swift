import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlOperatorContinueAfterParkPolicyTests: XCTestCase {

    private func singlePrimaryMission() -> (Mission, MissionRunEnvironment, MissionRunAssignment, RosterDevice) {
        let rd = UUID()
        let task = MissionTask(
            name: "Echo",
            enabled: true,
            cycles: 1,
            regularity: .continuous,
            rosterDeviceIds: [rd]
        )
        let device = RosterDevice(id: rd, name: "P1", vehicleClass: .ugvWheeled)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [device],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Echo:1",
            attachedFleetVehicleToken: "legacy:1",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(
                commanded: .policyCompleting,
                observed: .idle
            )
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignment])
        return (mission, run, assignment, device)
    }

    func test_policy_wind_down_retry_intent_flag() {
        XCTAssertTrue(MissionRunOperatorContinueAfterParkIntent.retryCompleteWindDown.isPolicyWindDownRetry)
        XCTAssertTrue(MissionRunOperatorContinueAfterParkIntent.retryAbortWindDown.isPolicyWindDownRetry)
        XCTAssertFalse(MissionRunOperatorContinueAfterParkIntent.resumeMission.isPolicyWindDownRetry)
        XCTAssertFalse(
            MissionRunOperatorContinueAfterParkIntent.unavailable(reason: "x").isPolicyWindDownRetry
        )
    }

    func test_retry_complete_when_recovery_wind_down_issued() {
        let (mission, run, assignment, device) = singlePrimaryMission()
        let taskID = mission.routeMacro.tasks[0].id
        run.status = .recovery
        run.setSessionPhase(.recovery)
        run.markMissionTaskCompleteWindDownIssued(forTaskID: taskID)
        run.refreshDerivedSquadStates()
        let fleet = FleetLinkService()
        let intent = MissionControlOperatorContinueAfterParkPolicy.resolve(
            assignment: assignment,
            rosterDevice: device,
            mission: mission,
            run: run,
            fleetLink: fleet,
            vehicleID: nil
        )
        XCTAssertEqual(intent, .retryCompleteWindDown)
    }

    func test_retry_abort_when_abort_wind_down_issued() {
        let (mission, run, assignment, device) = singlePrimaryMission()
        let taskID = mission.routeMacro.tasks[0].id
        run.setSessionPhase(.executing)
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskID)
        var row = assignment
        row.slotLifecycleLanes = MissionRunAssignmentSlotStateLanes(
            commanded: .policyAborting,
            observed: .idle
        )
        run.assignments = [row]
        run.refreshDerivedSquadStates()
        let fleet = FleetLinkService()
        let intent = MissionControlOperatorContinueAfterParkPolicy.resolve(
            assignment: row,
            rosterDevice: device,
            mission: mission,
            run: run,
            fleetLink: fleet,
            vehicleID: nil
        )
        XCTAssertEqual(intent, .retryAbortWindDown)
    }

    func test_wingman_without_policy_is_unavailable() {
        let leaderID = UUID()
        let wingID = UUID()
        let task = MissionTask(
            name: "Echo",
            enabled: true,
            cycles: 1,
            regularity: .continuous,
            rosterDeviceIds: [leaderID, wingID]
        )
        let leaderDevice = RosterDevice(id: leaderID, name: "P1", vehicleClass: .ugvWheeled)
        let wingDevice = RosterDevice(
            id: wingID,
            name: "W1",
            slot: .wingman,
            vehicleClass: .ugvWheeled,
            leaderRosterDeviceId: leaderID
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [leaderDevice, wingDevice],
            routeMacro: RouteMacro(tasks: [task])
        )
        let wingAssign = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: wingID,
            slotName: "W1",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    id: UUID(),
                    taskId: task.id,
                    rosterDeviceId: leaderID,
                    slotName: "Echo:1",
                    attachedFleetVehicleToken: "legacy:1"
                ),
                wingAssign,
            ]
        )
        run.status = .running
        run.setSessionPhase(.executing)
        run.refreshDerivedSquadStates()
        let fleet = FleetLinkService()
        let intent = MissionControlOperatorContinueAfterParkPolicy.resolve(
            assignment: wingAssign,
            rosterDevice: wingDevice,
            mission: mission,
            run: run,
            fleetLink: fleet,
            vehicleID: nil
        )
        guard case .unavailable = intent else {
            XCTFail("expected unavailable for wingman without end protocol, got \(intent)")
            return
        }
    }
}

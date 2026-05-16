import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlOperatorSquadTriageMissionControlPolicyTests: XCTestCase {

    private func twoSquadRun() -> (Mission, MissionRunEnvironment, MissionRunAssignment, MissionRunAssignment) {
        let rd1 = UUID()
        let rd2 = UUID()
        let task = MissionTask(name: "Dagger", enabled: true, regularity: .operatorTriggered, rosterDeviceIds: [rd1, rd2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "P1", vehicleClass: .uavCopter),
                RosterDevice(id: rd2, name: "P2", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "P1",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(UUID()).storageKey
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "P2",
            attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(UUID()).storageKey
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        return (mission, run, a1, a2)
    }

    func test_mission_row_park_when_executing_in_cycle() {
        let (mission, run, a1, _) = twoSquadRun()
        let task = mission.routeMacro.tasks[0]
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadActiveInCurrentCycle(a1.id)
        run.refreshDerivedTaskStates()
        let row = MissionControlOperatorSquadTriageMissionControlPolicy.resolvedMissionControlRow(
            run: run,
            task: task,
            assignment: a1,
            rosterDevice: mission.rosterDevices.first,
            mission: mission,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            vehicleID: "stream-1",
            squadState: run.squadStateByAssignmentID[a1.id] ?? .ready,
            now: Date()
        )
        XCTAssertEqual(row, .mission(.onMissionPark(offersLoiter: true)))
    }

    func test_mission_row_continue_when_operator_paused() {
        let (mission, run, a1, _) = twoSquadRun()
        let task = mission.routeMacro.tasks[0]
        let fleet = FleetLinkService()
        let sitl = SitlService()
        run.status = .running
        run.setSessionPhase(.executing)
        run.markMissionSquadOperatorPaused(forAssignmentID: a1.id)
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.squadStateByAssignmentID[a1.id], .paused)
        let row = MissionControlOperatorSquadTriageMissionControlPolicy.resolvedMissionControlRow(
            run: run,
            task: task,
            assignment: a1,
            rosterDevice: mission.rosterDevices.first,
            mission: mission,
            fleetLink: fleet,
            sitl: sitl,
            vehicleID: "vid",
            squadState: .paused,
            now: Date()
        )
        XCTAssertEqual(row, .mission(.pausedContinue))
    }

    func test_mission_row_hidden_during_recovery() {
        let (mission, run, a1, _) = twoSquadRun()
        let task = mission.routeMacro.tasks[0]
        run.status = .running
        run.setSessionPhase(.executing)
        run.markSquadCompletePolicyWindDownDispatchIssued(forAssignmentID: a1.id)
        run.refreshDerivedTaskStates()
        let row = MissionControlOperatorSquadTriageMissionControlPolicy.resolvedMissionControlRow(
            run: run,
            task: task,
            assignment: a1,
            rosterDevice: mission.rosterDevices.first,
            mission: mission,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            vehicleID: "v",
            squadState: run.squadStateByAssignmentID[a1.id] ?? .ready,
            now: Date()
        )
        XCTAssertEqual(row, .recovery)
    }
}

import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunOperatorLiveDriveHandoffGateTests: XCTestCase {

    func test_unionedMissionTaskIDsSuppressingAutopilotAutostart_merges_wind_down_and_live_drive_handoff() {
        let taskA = MissionTask(name: "Alpha")
        let taskB = MissionTask(name: "Bravo")
        let rdA = UUID()
        let rdB = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rdA, name: "P1", vehicleClass: .uavCopter),
                RosterDevice(id: rdB, name: "P2", vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [taskA, taskB])
        )
        let assignA = MissionRunAssignment(
            id: UUID(),
            taskId: taskA.id,
            rosterDeviceId: rdA,
            slotName: "A1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let assignB = MissionRunAssignment(
            id: UUID(),
            taskId: taskB.id,
            rosterDeviceId: rdB,
            slotName: "B1",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [assignA, assignB])
        run.markMissionTaskAbortWindDownIssued(forTaskID: taskA.id)
        run.noteOperatorLiveDriveHandoffActive(forAssignmentID: assignB.id)

        let union = run.unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission: mission)
        XCTAssertTrue(union.contains(taskA.id))
        XCTAssertTrue(union.contains(taskB.id))
    }

    func test_noteOperatorLiveDriveHandoffActive_ignores_unknown_assignment() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let roster = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "legacy:1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.noteOperatorLiveDriveHandoffActive(forAssignmentID: UUID())
        XCTAssertTrue(run.missionRunAssignmentIDsWithOperatorLiveDriveHandoff.isEmpty)
    }

    func test_clearOperatorLiveDriveHandoff_forAssignmentId() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let roster = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "legacy:1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.noteOperatorLiveDriveHandoffActive(forAssignmentID: roster.id)
        XCTAssertEqual(run.missionRunAssignmentIDsWithOperatorLiveDriveHandoff.count, 1)
        XCTAssertTrue(run.missionRunAssignmentIDsWithOperatorLiveDriveHandoff.contains(roster.id))
        run.clearOperatorLiveDriveHandoff(forAssignmentID: roster.id)
        XCTAssertTrue(run.missionRunAssignmentIDsWithOperatorLiveDriveHandoff.isEmpty)
    }

    func test_reserve_auto_swap_firstMatch_skips_handoff_assignment_before_distress() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let roster = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "legacy:1"
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.policies = MissionRunPolicies(
            engagement: MissionRunEngagementRules(perAction: [
                .swapInReserve: MissionRunEngagementRule(disposition: .autonomous),
            ])
        )
        run.noteOperatorLiveDriveHandoffActive(forAssignmentID: roster.id)
        run.attachServices(fleetLink: fleet, sitl: sitl)

        let match = MissionRunReserveAutoSwapLiveEvaluator.firstMatch(
            run: run,
            mission: mission,
            task: task,
            fleetLink: fleet,
            sitl: sitl,
            now: Date()
        )
        XCTAssertNil(match)
    }
}

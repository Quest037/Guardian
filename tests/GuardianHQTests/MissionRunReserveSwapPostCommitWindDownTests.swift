import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunReserveSwapPostCommitWindDownTests: XCTestCase {

    func test_buildReserveSwapPolicyWindDown_rtlForDisplacedPoolRow() {
        let task = MissionTask(name: "T")
        let rd = UUID()
        let poolId = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let sitlUUID = UUID()
        let displaced = MissionRunAssignment(
            id: poolId,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "pool",
            attachedFleetVehicleToken: "sitl:\(sitlUUID.uuidString)"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [displaced])
        let cmds = run.systems.executor.buildReserveSwapPolicyWindDownCommands(limitedToAssignmentIDs: [poolId])
        XCTAssertEqual(cmds.count, 1)
        XCTAssertEqual(cmds[0].issuerKey, MissionRunCommandIssuerKey.plannerReserveSwapPostCommit)
        guard case .recipe(let name, let params) = cmds[0].dispatch else {
            return XCTFail("expected recipe dispatch")
        }
        XCTAssertEqual(name, FleetMissionRecipeRegistrations.doReturnHomeRecipeName)
        XCTAssertEqual(params, .empty)
    }

    func test_buildReserveSwapPolicyWindDown_emptyWhenNoneOnlyOverride() {
        let task = MissionTask(name: "T")
        let rd = UUID()
        let poolId = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task], rules: RouteRules())
        )
        let sitlUUID = UUID()
        let displaced = MissionRunAssignment(
            id: poolId,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "pool",
            attachedFleetVehicleToken: "sitl:\(sitlUUID.uuidString)",
            policies: MissionRunAssignmentPolicies(reserveSwapPreferenceChain: [MissionRunReserveSwapTactic(kind: .none)])
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [displaced])
        let cmds = run.systems.executor.buildReserveSwapPolicyWindDownCommands(limitedToAssignmentIDs: [poolId])
        XCTAssertTrue(cmds.isEmpty)
    }
}

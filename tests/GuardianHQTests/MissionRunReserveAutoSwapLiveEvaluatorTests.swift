import Foundation
import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunReserveAutoSwapLiveEvaluatorTests: XCTestCase {

    func test_first_match_nil_when_swap_in_reserve_not_autonomous() {
        let primaryID = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [primaryID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let vacancy = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "P",
            attachedDevice: "x",
            attachedFleetVehicleToken: nil
        )
        var rules = MissionRunEngagementRules()
        rules.perAction[.swapInReserve] = MissionRunEngagementRule(disposition: .ask)
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.policies = MissionRunPolicies(engagement: rules)
        run.status = .running
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "R", attachedDevice: "pool"),
            ]),
            forTaskID: task.id
        )

        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        run.attachServices(fleetLink: fleet, sitl: sitl)

        XCTAssertNil(
            MissionRunReserveAutoSwapLiveEvaluator.firstMatch(
                run: run,
                mission: mission,
                task: task,
                fleetLink: fleet,
                sitl: sitl,
                now: Date()
            )
        )
    }
}

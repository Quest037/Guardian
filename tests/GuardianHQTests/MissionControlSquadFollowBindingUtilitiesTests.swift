import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlSquadFollowBindingUtilitiesTests: XCTestCase {

    func test_taskHasWingmen_trueWhenWingmanLeadsPrimaryOnTask() {
        let primaryID = UUID()
        let wingmanID = UUID()
        let task = MissionTask(name: "Patrol", enabled: true, rosterDeviceIds: [primaryID, wingmanID])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", role: .none, slot: .primary, vehicleClass: .uavCopter),
                RosterDevice(
                    id: wingmanID,
                    name: "W1",
                    role: .none,
                    slot: .wingman,
                    vehicleClass: .uavCopter,
                    leaderRosterDeviceId: primaryID
                ),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        XCTAssertTrue(MissionControlSquadFollowBindingUtilities.taskHasWingmen(mission: mission, task: task))
    }

    func test_resolvedSquadFormationSpacing_primarySlotOverrideWins() {
        let taskID = UUID()
        let primaryDeviceID = UUID()
        let wingmanDeviceID = UUID()
        let primaryAssignmentID = UUID()
        var task = MissionTask(id: taskID, name: "T", rosterDeviceIds: [primaryDeviceID, wingmanDeviceID])
        task.squadFormationSpacing = .normal
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryDeviceID, name: "P", role: .none, slot: .primary, vehicleClass: .uavCopter),
                RosterDevice(
                    id: wingmanDeviceID,
                    name: "W",
                    role: .none,
                    slot: .wingman,
                    vehicleClass: .uavCopter,
                    leaderRosterDeviceId: primaryDeviceID
                ),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            id: primaryAssignmentID,
            taskId: taskID,
            rosterDeviceId: primaryDeviceID,
            slotName: "P1",
            policies: MissionRunAssignmentPolicies(squadFormationSpacingOverride: .tight)
        )
        XCTAssertEqual(
            MissionRunPolicyResolution.resolvedSquadFormationSpacing(assignment: assignment, mission: mission),
            .tight
        )
    }

    func test_resolvedSquadFormation_primarySlotOverrideWins() {
        let taskID = UUID()
        let primaryDeviceID = UUID()
        let wingmanDeviceID = UUID()
        let primaryAssignmentID = UUID()
        var task = MissionTask(id: taskID, name: "T", rosterDeviceIds: [primaryDeviceID, wingmanDeviceID])
        task.squadFormation = .chevron
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryDeviceID, name: "P", role: .none, slot: .primary, vehicleClass: .uavCopter),
                RosterDevice(
                    id: wingmanDeviceID,
                    name: "W",
                    role: .none,
                    slot: .wingman,
                    vehicleClass: .uavCopter,
                    leaderRosterDeviceId: primaryDeviceID
                ),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignment = MissionRunAssignment(
            id: primaryAssignmentID,
            taskId: taskID,
            rosterDeviceId: primaryDeviceID,
            slotName: "P1",
            policies: MissionRunAssignmentPolicies(squadFormationOverride: .arrowhead)
        )
        XCTAssertEqual(
            MissionRunPolicyResolution.resolvedSquadFormation(assignment: assignment, mission: mission),
            .arrowhead
        )
        XCTAssertEqual(
            MissionRunPolicyResolution.inheritedSquadFormationForPrimarySlot(assignment: assignment, mission: mission),
            .chevron
        )
    }

    func test_taskHasWingmen_falseWithoutWingmanRows() {
        let primaryID = UUID()
        let task = MissionTask(name: "Solo", enabled: true, rosterDeviceIds: [primaryID])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", role: .none, slot: .primary, vehicleClass: .uavCopter),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        XCTAssertFalse(MissionControlSquadFollowBindingUtilities.taskHasWingmen(mission: mission, task: task))
    }

    func test_squadFollowStatusRevision_incrementsOnRosterRelease() {
        let primaryID = UUID()
        let wingmanID = UUID()
        let task = MissionTask(name: "T", enabled: true, rosterDeviceIds: [primaryID, wingmanID])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "P", role: .none, slot: .primary, vehicleClass: .uavCopter),
                RosterDevice(
                    id: wingmanID,
                    name: "W",
                    role: .none,
                    slot: .wingman,
                    vehicleClass: .uavCopter,
                    leaderRosterDeviceId: primaryID
                ),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let primary = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "T:1",
            attachedFleetVehicleToken: "legacy:1"
        )
        let wingman = MissionRunAssignment(
            taskId: task.id,
            rosterDeviceId: wingmanID,
            slotName: "T:W1",
            attachedFleetVehicleToken: "legacy:2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [primary, wingman])
        let fleetLink = FleetLinkService()
        let sitl = SitlService()
        let revisionBefore = run.squadFollowStatusRevision
        _ = run.performRosterReleaseWingmanFromSquadFollow(
            wingmanAssignmentID: wingman.id,
            primaryAssignmentID: primary.id,
            fleetLink: fleetLink,
            sitl: sitl,
            dispatchPark: false
        )
        XCTAssertEqual(run.squadFollowStatusRevision, revisionBefore + 1)
        XCTAssertTrue(run.isMissionRunRosterReleasedFromSquadFollow(assignmentID: wingman.id))
    }
}

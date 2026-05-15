import XCTest

@testable import GuardianHQ

@MainActor
final class MCRLiveRosterStripAssignmentFilterTests: XCTestCase {
    func test_filteredAssignments_nilMission_returnsAllAssignments() {
        let mission = Mission(name: "M", description: "", type: .mobile)
        let a1 = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "A")
        let a2 = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "B")
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        let out = MCRLiveRosterStripAssignmentFilter.filteredAssignments(run: run, mission: nil, focusedLiveTaskID: UUID())
        XCTAssertEqual(out.map(\.id), [a1.id, a2.id])
    }

    func test_assignmentMatchesLiveFocus_nilFocus_allMatch() {
        let mission = Mission(
            name: "m",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [
                MissionTask(id: UUID(), name: "T1", enabled: true),
            ])
        )
        let assignment = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "P")
        XCTAssertTrue(
            MCRLiveRosterStripAssignmentFilter.assignmentMatchesLiveFocus(
                assignment,
                mission: mission,
                focusedLiveTaskID: nil
            )
        )
    }

    func test_singleEnabledTask_focusIncludesUnboundSlots() {
        let taskID = UUID()
        let mission = Mission(
            name: "m",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [
                MissionTask(id: taskID, name: "Only", enabled: true),
                MissionTask(id: UUID(), name: "Off", enabled: false),
            ])
        )
        let bound = MissionRunAssignment(taskId: taskID, rosterDeviceId: UUID(), slotName: "P")
        let unbound = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "W")
        XCTAssertTrue(
            MCRLiveRosterStripAssignmentFilter.assignmentMatchesLiveFocus(
                bound,
                mission: mission,
                focusedLiveTaskID: taskID
            )
        )
        XCTAssertTrue(
            MCRLiveRosterStripAssignmentFilter.assignmentMatchesLiveFocus(
                unbound,
                mission: mission,
                focusedLiveTaskID: taskID
            )
        )
    }
}

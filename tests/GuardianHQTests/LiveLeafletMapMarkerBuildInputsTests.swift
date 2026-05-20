import XCTest

@testable import GuardianCore

@MainActor
final class LiveLeafletMapMarkerBuildInputsTests: XCTestCase {

    func test_assignment_matches_task_focus_single_enabled_task_fallback() {
        let missionID = UUID()
        let loneTaskID = UUID()
        let mission = Mission(
            id: missionID,
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(
                tasks: [
                    MissionTask(id: loneTaskID, name: "T", enabled: true, waypoints: []),
                ]
            )
        )
        let unscoped = MissionRunAssignment(
            id: UUID(),
            taskId: nil,
            rosterDeviceId: UUID(),
            slotName: "S"
        )
        XCTAssertTrue(
            LiveLeafletMapMarkerFocus.assignmentMatchesTaskFocus(
                unscoped,
                mission: mission,
                taskFocusID: loneTaskID
            )
        )
        let otherTask = UUID()
        XCTAssertFalse(
            LiveLeafletMapMarkerFocus.assignmentMatchesTaskFocus(
                unscoped,
                mission: mission,
                taskFocusID: otherTask
            )
        )
    }

    func test_filtered_roster_nil_scope_returns_all() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let a = MissionRunAssignment(id: UUID(), rosterDeviceId: UUID(), slotName: "A")
        let b = MissionRunAssignment(id: UUID(), rosterDeviceId: UUID(), slotName: "B")
        let filtered = LiveLeafletMapMarkerFocus.filteredRosterAssignments(
            [a, b],
            mission: mission,
            scope: LiveLeafletMapMarkerRosterScope(taskFocusID: nil)
        )
        XCTAssertEqual(filtered.count, 2)
    }

    func test_floating_reserve_pool_task_ids_map_isolation() {
        let tid = UUID()
        let other = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(
                tasks: [
                    MissionTask(id: tid, name: "A", enabled: true, waypoints: []),
                    MissionTask(id: other, name: "B", enabled: true, waypoints: []),
                ]
            )
        )
        let focused = LiveLeafletMapMarkerFocus.floatingReservePoolTaskIDs(
            mission: mission,
            mapFocusedTaskID: tid
        )
        XCTAssertEqual(focused, [tid])
        let allEnabled = LiveLeafletMapMarkerFocus.floatingReservePoolTaskIDs(
            mission: mission,
            mapFocusedTaskID: nil
        )
        XCTAssertEqual(Set(allEnabled), Set([tid, other]))
    }

    func test_mission_control_live_overview_roster_scope_when_isolated() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        let fleetLink = FleetLinkService()
        let sitl = SitlService()
        let focusTask = UUID()
        let inputs = LiveLeafletMapMarkerBuildInputs.missionControlLiveOverview(
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            isolateMapToSelectedTask: true,
            triageFocusedTaskID: focusTask,
            presentation: LiveLeafletMapMarkerPresentationState(),
            reservePoolPresentation: LiveLeafletMapReservePoolPresentationState()
        )
        XCTAssertEqual(inputs.rosterScope.taskFocusID, focusTask)
        XCTAssertEqual(inputs.floatingReservePoolScope.taskIDs, [focusTask])
    }

    func test_mission_control_live_overview_full_mission_roster_when_not_isolated() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let run = MissionRunEnvironment(mission: mission)
        let inputs = LiveLeafletMapMarkerBuildInputs.missionControlLiveOverview(
            run: run,
            mission: mission,
            fleetLink: FleetLinkService(),
            sitl: SitlService(),
            isolateMapToSelectedTask: false,
            triageFocusedTaskID: UUID(),
            presentation: LiveLeafletMapMarkerPresentationState(),
            reservePoolPresentation: LiveLeafletMapReservePoolPresentationState()
        )
        XCTAssertNil(inputs.rosterScope.taskFocusID)
    }
}

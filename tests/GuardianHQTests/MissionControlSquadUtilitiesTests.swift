import XCTest

@testable import GuardianCore

@MainActor
final class MissionControlSquadUtilitiesTests: XCTestCase {

    func test_squad_display_name_is_one_based() {
        XCTAssertEqual(MissionControlSquadUtilities.squadDisplayName(taskName: "Dagger", squadIndex: 0), "Dagger:1")
        XCTAssertEqual(MissionControlSquadUtilities.squadDisplayName(taskName: "Dagger", squadIndex: 2), "Dagger:3")
    }

    func test_ordered_primaries_follow_roster_device_ids_order() {
        let p1 = RosterDevice(id: UUID(), name: "P1", slot: .primary)
        let p2 = RosterDevice(id: UUID(), name: "P2", slot: .primary)
        let p3 = RosterDevice(id: UUID(), name: "P3", slot: .primary)
        let task = MissionTask(
            name: "Dagger",
            waypoints: [RouteWaypoint(coord: RouteCoordinate(lat: 1, lon: 2))],
            rosterDeviceIds: [p2.id, p1.id, p3.id]
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p1.id,
            slotName: "P1",
            attachedFleetVehicleToken: "tok-1"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p2.id,
            slotName: "P2",
            attachedFleetVehicleToken: "tok-2"
        )
        let a3 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p3.id,
            slotName: "P3",
            attachedFleetVehicleToken: "tok-3"
        )
        let ordered = MissionControlSquadUtilities.orderedPrimarySquads(
            task: task,
            assignments: [a3, a1, a2],
            rosterDevices: [p1, p2, p3],
            enabledTaskCount: 1
        )
        XCTAssertEqual(ordered.map(\.primary.id), [p2.id, p1.id, p3.id])
    }

    func test_build_task_squad_missions_assigns_squad_index_and_items() {
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(
            name: "Dagger",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 0, lon: 0)),
                RouteWaypoint(coord: RouteCoordinate(lat: 1, lon: 1)),
            ],
            rosterDeviceIds: [p1.id, p2.id]
        )
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    taskId: task.id,
                    rosterDeviceId: p1.id,
                    slotName: "P1",
                    attachedFleetVehicleToken: "a"
                ),
                MissionRunAssignment(
                    taskId: task.id,
                    rosterDeviceId: p2.id,
                    slotName: "P2",
                    attachedFleetVehicleToken: "b"
                ),
            ]
        )
        let squads = run.systems.planner.buildTaskSquadMissions(mission: mission, taskId: task.id)
        XCTAssertEqual(squads.count, 2)
        XCTAssertEqual(squads[0].squadIndex, 0)
        XCTAssertEqual(squads[1].squadIndex, 1)
        XCTAssertEqual(squads[0].missionItems.count, 2)
        XCTAssertEqual(
            MissionControlSquadUtilities.squadDisplayName(taskName: task.name, squadIndex: squads[1].squadIndex),
            "Dagger:2"
        )
    }

    func test_live_log_primary_squad_task_chip_nil_when_only_one_bound_primary() {
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(name: "Dagger", rosterDeviceIds: [p1.id, p2.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p1.id,
            slotName: "P1",
            attachedFleetVehicleToken: "a"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p2.id,
            slotName: "P2",
            attachedFleetVehicleToken: nil
        )
        XCTAssertNil(
            MissionControlSquadUtilities.liveLogPrimarySquadTaskChipIfApplicable(
                assignmentID: a1.id,
                mission: mission,
                assignments: [a1, a2]
            )
        )
    }

    func test_live_log_primary_squad_task_chip_one_based_per_roster_order() {
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(name: "Dagger", rosterDeviceIds: [p1.id, p2.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p1.id,
            slotName: "P1",
            attachedFleetVehicleToken: "a"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p2.id,
            slotName: "P2",
            attachedFleetVehicleToken: "b"
        )
        let chip1 = MissionControlSquadUtilities.liveLogPrimarySquadTaskChipIfApplicable(
            assignmentID: a1.id,
            mission: mission,
            assignments: [a1, a2]
        )
        let chip2 = MissionControlSquadUtilities.liveLogPrimarySquadTaskChipIfApplicable(
            assignmentID: a2.id,
            mission: mission,
            assignments: [a1, a2]
        )
        XCTAssertEqual(chip1?.chipLabel, "Dagger:1")
        XCTAssertEqual(chip2?.chipLabel, "Dagger:2")
    }

    func test_resolved_task_log_prefix_vehicle_slot_uses_squad_chip() {
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(name: "Dagger", rosterDeviceIds: [p1.id, p2.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p1.id,
            slotName: "P1",
            attachedFleetVehicleToken: "a"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p2.id,
            slotName: "P2",
            attachedFleetVehicleToken: "b"
        )
        let event = MissionRunEvent(
            speaker: .vehicleSlot("P2"),
            message: "test",
            templateParams: [:]
        )
        XCTAssertEqual(
            event.resolvedTaskLogPrefix(mission: mission, assignments: [a1, a2]),
            "Dagger:2"
        )
    }

    func test_resolved_task_log_prefix_slot_id_param_uses_squad_chip() {
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(name: "Dagger", rosterDeviceIds: [p1.id, p2.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task])
        )
        let a1 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p1.id,
            slotName: "P1",
            attachedFleetVehicleToken: "a"
        )
        let a2 = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: p2.id,
            slotName: "P2",
            attachedFleetVehicleToken: "b"
        )
        let event = MissionRunEvent(
            speaker: .missionControl,
            message: "test",
            templateParams: ["slotID": a1.id.uuidString]
        )
        XCTAssertEqual(
            event.resolvedTaskLogPrefix(mission: mission, assignments: [a1, a2]),
            "Dagger:1"
        )
    }

    func test_plan_compiler_uses_multi_vehicle_team_when_two_primaries_on_one_task() {
        let p1 = RosterDevice(name: "P1", slot: .primary)
        let p2 = RosterDevice(name: "P2", slot: .primary)
        let task = MissionTask(name: "Dagger", rosterDeviceIds: [p1.id, p2.id])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [p1, p2],
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(taskId: task.id, rosterDeviceId: p1.id, slotName: "P1", attachedFleetVehicleToken: "a"),
                MissionRunAssignment(taskId: task.id, rosterDeviceId: p2.id, slotName: "P2", attachedFleetVehicleToken: "b"),
            ]
        )
        let plan = MissionControlPlanCompiler.compile(run: run, mission: mission, fleetVehicles: [])
        XCTAssertEqual(plan.teamTopology, .multiVehicleTeam)
        XCTAssertEqual(plan.taskTopology, .singleTask)
    }

    func test_live_squad_row_display_state_uses_squad_state_not_task_recovery_while_executing() {
        let s = MissionControlSquadUtilities.liveSquadRowDisplayTaskState(
            taskRollup: .recovery,
            squadState: .executing
        )
        XCTAssertEqual(s, .executing)
    }

    func test_live_squad_row_display_state_keeps_completed_when_squad_completed() {
        let s = MissionControlSquadUtilities.liveSquadRowDisplayTaskState(
            taskRollup: .recovery,
            squadState: .completed
        )
        XCTAssertEqual(s, .completed)
    }

    func test_live_squad_row_display_state_between_stays_between_even_when_task_aborting() {
        let s = MissionControlSquadUtilities.liveSquadRowDisplayTaskState(
            taskRollup: .aborting,
            squadState: .between
        )
        XCTAssertEqual(s, .between)
    }
}

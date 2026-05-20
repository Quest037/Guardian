import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunLiveTaskLogEventFilterTests: XCTestCase {
    func test_filter_includes_task_tagged_and_vehicle_slot_lines_for_focus() {
        let taskA = UUID()
        let taskB = UUID()
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(
                tasks: [
                    MissionTask(id: taskA, name: "Alpha", enabled: true),
                    MissionTask(id: taskB, name: "Bravo", enabled: true),
                ]
            )
        )
        let roster = UUID()
        let assignments = [
            MissionRunAssignment(
                id: UUID(),
                taskId: taskA,
                rosterDeviceId: roster,
                slotName: "SlotA"
            ),
            MissionRunAssignment(
                id: UUID(),
                taskId: taskB,
                rosterDeviceId: roster,
                slotName: "SlotB"
            ),
        ]
        let events: [MissionRunEvent] = [
            MissionRunEvent(taskID: taskA, message: "on task a", templateKey: "t.a"),
            MissionRunEvent(taskID: taskB, message: "on task b", templateKey: "t.b"),
            MissionRunEvent(
                taskID: nil,
                speaker: .vehicleSlot("SlotA"),
                message: "telemetry",
                templateKey: "t.telemetry"
            ),
            MissionRunEvent(
                taskID: nil,
                speaker: .vehicleSlot("SlotB"),
                message: "other slot",
                templateKey: "t.other"
            ),
        ]
        let filtered = MissionRunEnvironment.filterEventsForLiveTaskLogFocus(
            events: events,
            assignments: assignments,
            mission: mission,
            focusedTaskID: taskA
        )
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.taskID == taskA })
        XCTAssertTrue(filtered.contains { $0.speaker == .vehicleSlot("SlotA") })
    }

    func test_filter_single_enabled_task_includes_nil_task_id_assignment_slot_lines() {
        let onlyTask = UUID()
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(
                tasks: [
                    MissionTask(id: onlyTask, name: "Only", enabled: true),
                ]
            )
        )
        let roster = UUID()
        let assignments = [
            MissionRunAssignment(
                id: UUID(),
                taskId: nil,
                rosterDeviceId: roster,
                slotName: "Solo"
            ),
        ]
        let events: [MissionRunEvent] = [
            MissionRunEvent(
                taskID: nil,
                speaker: .vehicleSlot("Solo"),
                message: "hub",
                templateKey: "x"
            ),
        ]
        let filtered = MissionRunEnvironment.filterEventsForLiveTaskLogFocus(
            events: events,
            assignments: assignments,
            mission: mission,
            focusedTaskID: onlyTask
        )
        XCTAssertEqual(filtered.count, 1)
    }
}

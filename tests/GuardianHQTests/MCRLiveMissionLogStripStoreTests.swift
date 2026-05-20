import XCTest

@testable import GuardianCore

@MainActor
final class MCRLiveMissionLogStripStoreTests: XCTestCase {
    func test_ingest_tail_matches_filter_suffix_cap() {
        let store = MCRLiveMissionLogStripStore()
        let mission = Mission(name: "M", description: "", type: .mobile)
        var run = MissionRunEnvironment(mission: mission)
        for i in 0 ..< 100 {
            run.appendEvent(
                MissionRunEvent(
                    taskID: nil,
                    speaker: .missionControl,
                    message: "wide \(i)"
                )
            )
        }
        store.ingestFromRun(run, mission: mission, focusedTaskID: nil)
        XCTAssertEqual(store.visibleTail.count, MCRLiveMissionLogStripStore.visibleTailCount)
        XCTAssertEqual(store.visibleTail.first?.message, "wide 20")
        XCTAssertEqual(store.visibleTail.last?.message, "wide 99")
        XCTAssertEqual(store.tailAnchorID, store.visibleTail.last?.id)
    }

    func test_ingest_skipsPublishWhenTailUnchanged() {
        let store = MCRLiveMissionLogStripStore()
        let mission = Mission(name: "M", description: "", type: .mobile)
        var run = MissionRunEnvironment(mission: mission)
        run.appendEvent(MissionRunEvent(taskID: nil, speaker: .missionControl, message: "one"))
        store.ingestFromRun(run, mission: mission, focusedTaskID: nil)
        let firstIDs = store.visibleTail.map(\.id)
        store.ingestFromRun(run, mission: mission, focusedTaskID: nil)
        let secondIDs = store.visibleTail.map(\.id)
        XCTAssertEqual(firstIDs, secondIDs)
    }

    func test_ingest_focusedTask_includes_task_tagged_and_slot_narrative() {
        let rd = RosterDevice(name: "Alpha", slot: .primary, vehicleClass: .uavCopter)
        var task = MissionTask(name: "T1", enabled: true, rosterDeviceIds: [rd.id])
        var mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [task])
        )
        task = mission.routeMacro.tasks[0]
        let row = MissionRunAssignment(taskId: task.id, rosterDeviceId: rd.id, slotName: "Alpha")
        var run = MissionRunEnvironment(mission: mission, assignments: [row])

        run.appendEvent(MissionRunEvent(taskID: task.id, speaker: .missionControl, message: "task line"))
        run.appendEvent(
            MissionRunEvent(
                taskID: nil,
                speaker: .vehicleSlot("Alpha"),
                message: "slot line"
            )
        )
        run.appendEvent(
            MissionRunEvent(
                taskID: nil,
                speaker: .vehicleSlot("Other"),
                message: "other slot"
            )
        )

        let store = MCRLiveMissionLogStripStore()
        store.ingestFromRun(run, mission: mission, focusedTaskID: task.id)
        let messages = store.visibleTail.map(\.message)
        XCTAssertTrue(messages.contains("task line"))
        XCTAssertTrue(messages.contains("slot line"))
        XCTAssertFalse(messages.contains("other slot"))
    }
}

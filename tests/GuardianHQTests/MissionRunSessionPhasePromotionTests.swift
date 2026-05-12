import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunSessionPhasePromotionTests: XCTestCase {

    private func environment(tasks: [MissionTask]) -> MissionRunEnvironment {
        var rosterDevices: [RosterDevice] = []
        for task in tasks {
            for deviceId in task.rosterDeviceIds {
                if !rosterDevices.contains(where: { $0.id == deviceId }) {
                    rosterDevices.append(RosterDevice(id: deviceId, name: "Slot-\(deviceId.uuidString.prefix(6))"))
                }
            }
        }
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: rosterDevices,
            routeMacro: RouteMacro(tasks: tasks)
        )
        return MissionRunEnvironment(mission: mission)
    }

    func test_aborting_promotes_to_aborted_when_all_enabled_tasks_acknowledged() {
        let d1 = UUID()
        let d2 = UUID()
        let t1 = MissionTask(name: "A", rosterDeviceIds: [d1])
        let t2 = MissionTask(name: "B", rosterDeviceIds: [d2])
        let run = environment(tasks: [t1, t2])
        run.status = .running
        run.setSessionPhase(.aborting)
        run.acknowledgeTaskMissionEndAbort(taskID: t1.id)
        XCTAssertEqual(run.sessionPhase, .aborting)
        run.acknowledgeTaskMissionEndAbort(taskID: t2.id)
        XCTAssertEqual(run.sessionPhase, .aborted)
    }

    func test_aborting_promotes_when_paused() {
        let d1 = UUID()
        let d2 = UUID()
        let t1 = MissionTask(name: "A", rosterDeviceIds: [d1])
        let t2 = MissionTask(name: "B", rosterDeviceIds: [d2])
        let run = environment(tasks: [t1, t2])
        run.status = .paused
        run.setSessionPhase(.aborting)
        run.acknowledgeTaskMissionEndAbort(taskID: t1.id)
        run.acknowledgeTaskMissionEndAbort(taskID: t2.id)
        XCTAssertEqual(run.sessionPhase, .aborted)
    }

    func test_disabled_tasks_excluded_from_abort_promotion_denominator() {
        let d1 = UUID()
        let d2 = UUID()
        let enabled = MissionTask(name: "On", enabled: true, rosterDeviceIds: [d1])
        let disabled = MissionTask(name: "Off", enabled: false, rosterDeviceIds: [d2])
        let run = environment(tasks: [enabled, disabled])
        run.status = .running
        run.setSessionPhase(.aborting)
        run.acknowledgeTaskMissionEndAbort(taskID: enabled.id)
        XCTAssertEqual(run.sessionPhase, .aborted)
    }

    func test_aborting_stays_until_all_enabled_tasks_acknowledged() {
        let d1 = UUID()
        let d2 = UUID()
        let t1 = MissionTask(name: "A", rosterDeviceIds: [d1])
        let t2 = MissionTask(name: "B", rosterDeviceIds: [d2])
        let run = environment(tasks: [t1, t2])
        run.status = .running
        run.setSessionPhase(.aborting)
        run.acknowledgeTaskMissionEndAbort(taskID: t1.id)
        XCTAssertEqual(run.sessionPhase, .aborting)
    }

    func test_acknowledge_abort_does_not_promote_when_session_not_aborting() {
        let d1 = UUID()
        let t1 = MissionTask(name: "A", rosterDeviceIds: [d1])
        let run = environment(tasks: [t1])
        run.status = .running
        run.setSessionPhase(.executing)
        run.acknowledgeTaskMissionEndAbort(taskID: t1.id)
        XCTAssertEqual(run.sessionPhase, .executing)
    }
}

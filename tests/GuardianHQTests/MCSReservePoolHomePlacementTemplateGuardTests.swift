import XCTest

@testable import GuardianCore

final class MCSReservePoolHomePlacementTemplateGuardTests: XCTestCase {

    func test_not_armed_never_disarms() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let tid = UUID()
        mission.routeMacro.tasks = [MissionTask(id: tid, name: "Alpha", enabled: true)]
        XCTAssertFalse(MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(armedTaskID: nil, mission: mission))
        XCTAssertFalse(MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(armedTaskID: nil, mission: nil))
    }

    func test_mission_nil_disarms_when_armed() {
        let tid = UUID()
        XCTAssertTrue(MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(armedTaskID: tid, mission: nil))
    }

    func test_missing_task_disarms() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        mission.routeMacro.tasks = [MissionTask(id: UUID(), name: "Other", enabled: true)]
        let missing = UUID()
        XCTAssertTrue(MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(armedTaskID: missing, mission: mission))
    }

    func test_disabled_task_disarms() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let tid = UUID()
        mission.routeMacro.tasks = [MissionTask(id: tid, name: "Alpha", enabled: false)]
        XCTAssertTrue(MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(armedTaskID: tid, mission: mission))
    }

    func test_enabled_task_stays_armed() {
        var mission = Mission(name: "M", description: "", type: .mobile)
        let tid = UUID()
        mission.routeMacro.tasks = [MissionTask(id: tid, name: "Alpha", enabled: true)]
        XCTAssertFalse(MCSReservePoolHomePlacementTemplateGuard.shouldDisarmPoolHomeArm(armedTaskID: tid, mission: mission))
    }
}

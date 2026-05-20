import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunReserveSwapPhaseLogEmissionTests: XCTestCase {

    func test_append_reserve_swap_phase_log_sets_catalog_template_key() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        let slot = MissionRunReservePoolSlot(label: "P1", attachedDevice: "a")
        let cor = MissionRunReserveRecipeRunnerCorrelation.floatingPoolReserve(
            missionRunID: run.id,
            missionTaskID: task.id,
            vacancyAssignmentID: UUID(),
            poolSlot: slot,
            vehicleID: "sysid:9"
        )
        run.appendReserveSwapPipelinePhaseLog(phase: .missionUpload, passed: false, correlation: cor, detail: "unit probe")
        let last = run.events.last
        XCTAssertEqual(
            last?.templateKey,
            MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .missionUpload, passed: false)
        )
        XCTAssertEqual(last?.templateParams["phase"], "mission_upload")
        XCTAssertEqual(last?.templateParams["vehicleID"], "sysid:9")
        XCTAssertEqual(last?.templateParams["detail"], "unit probe")
    }
}

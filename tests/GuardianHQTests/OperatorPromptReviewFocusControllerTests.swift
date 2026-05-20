import XCTest

@testable import GuardianCore

@MainActor
final class OperatorPromptReviewFocusControllerTests: XCTestCase {

    func test_requestLiveDriveEngageDrillIn_seeds_vehicle_run_and_live_drive_section() {
        let c = OperatorPromptReviewFocusController()
        let vehicleID = "sysid:3"
        let liveRun = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        c.requestLiveDriveEngageDrillIn(vehicleID: vehicleID, missionRunID: liveRun)
        XCTAssertEqual(c.pendingPrimarySection, .liveDrive)
        XCTAssertEqual(c.pendingLiveDriveVehicleID, vehicleID)
        XCTAssertEqual(c.pendingLiveDriveMissionRunID, liveRun)
        XCTAssertNil(c.pendingMissionControlRunID)
        XCTAssertNil(c.pendingMissionControlMissionTaskID)
        XCTAssertNil(c.pendingMissionControlLiveAssignmentID)
    }

    func test_consumeLiveDriveFocus_clears_only_pending_vehicle_id() {
        let c = OperatorPromptReviewFocusController()
        let liveRun = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        c.requestLiveDriveEngageDrillIn(vehicleID: "sysid:1", missionRunID: liveRun)
        c.consumeLiveDriveFocus()
        XCTAssertNil(c.pendingLiveDriveVehicleID)
        XCTAssertEqual(c.pendingLiveDriveMissionRunID, liveRun)
    }

    func test_consumePendingLiveDriveMissionRunDrillIn_clears_mission_run() {
        let c = OperatorPromptReviewFocusController()
        c.requestLiveDriveEngageDrillIn(vehicleID: "sysid:1", missionRunID: UUID())
        c.consumePendingLiveDriveMissionRunDrillIn()
        XCTAssertNil(c.pendingLiveDriveMissionRunID)
    }

    func test_requestMissionControlReturnDrillIn_seeds_run_task_and_mission_control_section() {
        let c = OperatorPromptReviewFocusController()
        let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
        let taskID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        c.requestLiveDriveEngageDrillIn(vehicleID: "sysid:2", missionRunID: runID)
        c.requestMissionControlReturnDrillIn(runID: runID, missionTaskID: taskID)
        XCTAssertEqual(c.pendingPrimarySection, .missionControl)
        XCTAssertEqual(c.pendingMissionControlRunID, runID)
        XCTAssertEqual(c.pendingMissionControlMissionTaskID, taskID)
        XCTAssertNil(c.pendingMissionControlLiveAssignmentID)
        XCTAssertNil(c.pendingLiveDriveVehicleID)
        XCTAssertNil(c.pendingLiveDriveMissionRunID)
    }

    func test_requestMissionControlReturnDrillIn_seeds_live_assignment_id_when_passed() {
        let c = OperatorPromptReviewFocusController()
        let runID = UUID(uuidString: "31000000-0000-0000-0000-000000000031")!
        let aid = UUID(uuidString: "32000000-0000-0000-0000-000000000032")!
        c.requestMissionControlReturnDrillIn(runID: runID, missionTaskID: nil, liveAssignmentID: aid)
        XCTAssertEqual(c.pendingMissionControlRunID, runID)
        XCTAssertNil(c.pendingMissionControlMissionTaskID)
        XCTAssertEqual(c.pendingMissionControlLiveAssignmentID, aid)
    }
}

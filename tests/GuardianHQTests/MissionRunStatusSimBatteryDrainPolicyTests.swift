import XCTest
@testable import GuardianHQ

final class MissionRunStatusSimBatteryDrainPolicyTests: XCTestCase {
    func test_running_appliesMissionRunSimBatteryDrainFromOperatorSettings() {
        XCTAssertTrue(MissionRunStatus.running.appliesMissionRunSimBatteryDrainFromOperatorSettings)
    }

    func test_recovery_appliesMissionRunSimBatteryDrainFromOperatorSettings() {
        XCTAssertTrue(MissionRunStatus.recovery.appliesMissionRunSimBatteryDrainFromOperatorSettings)
    }

    func test_setup_paused_completed_doNotApplyMissionRunSimBatteryDrainFromOperatorSettings() {
        XCTAssertFalse(MissionRunStatus.setup.appliesMissionRunSimBatteryDrainFromOperatorSettings)
        XCTAssertFalse(MissionRunStatus.paused.appliesMissionRunSimBatteryDrainFromOperatorSettings)
        XCTAssertFalse(MissionRunStatus.completed.appliesMissionRunSimBatteryDrainFromOperatorSettings)
    }
}

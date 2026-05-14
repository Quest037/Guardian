import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunSimCleanupRemovalTriggerTests: XCTestCase {
    func test_shouldTriggerSimCleanupBeforeRemoval_running_isTrue() {
        let run = MissionRunEnvironment(
            missionId: UUID(),
            missionName: "Alpha",
            status: .running,
            assignments: []
        )
        XCTAssertTrue(run.shouldTriggerSimCleanupBeforeRemoval())
    }

    func test_shouldTriggerSimCleanupBeforeRemoval_completed_isTrue() {
        let run = MissionRunEnvironment(
            missionId: UUID(),
            missionName: "Bravo",
            status: .completed,
            assignments: []
        )
        XCTAssertTrue(run.shouldTriggerSimCleanupBeforeRemoval())
    }

    func test_shouldTriggerSimCleanupBeforeRemoval_setup_withoutFleetServices_isFalse() {
        let run = MissionRunEnvironment(
            missionId: UUID(),
            missionName: "Charlie",
            status: .setup,
            assignments: []
        )
        XCTAssertFalse(run.shouldTriggerSimCleanupBeforeRemoval())
    }
}

import XCTest

@testable import GuardianHQ

final class MissionRunSimCleanupOperatorToastCopyTests: XCTestCase {
    func test_partialFailureMessage_nilWhenClean() {
        XCTAssertNil(
            MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
                simKillFailedCount: 0,
                shouldTeleport: true,
                rosterSnapshotCount: 1,
                rosterSkipped: 0,
                poolSnapshotCount: 0,
                poolSkipped: 0
            )
        )
    }

    func test_partialFailureMessage_simKillOnly() {
        let m = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
            simKillFailedCount: 2,
            shouldTeleport: false,
            rosterSnapshotCount: 0,
            rosterSkipped: 0,
            poolSnapshotCount: 0,
            poolSkipped: 0
        )
        XCTAssertTrue((m ?? "").contains("SIM kill did not succeed for 2 vehicles"))
    }

    func test_partialFailureMessage_rosterSkips() {
        let m = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
            simKillFailedCount: 0,
            shouldTeleport: true,
            rosterSnapshotCount: 2,
            rosterSkipped: 1,
            poolSnapshotCount: 0,
            poolSkipped: 0
        )
        XCTAssertTrue((m ?? "").contains("roster home restore skipped one vehicle"))
    }

    func test_partialFailureMessage_combined() throws {
        let m = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
            simKillFailedCount: 1,
            shouldTeleport: true,
            rosterSnapshotCount: 1,
            rosterSkipped: 1,
            poolSnapshotCount: 1,
            poolSkipped: 2
        )
        let s = try XCTUnwrap(m)
        XCTAssertTrue(s.contains("SIM kill"))
        XCTAssertTrue(s.contains("roster"))
        XCTAssertTrue(s.contains("reserve pool"))
    }
}

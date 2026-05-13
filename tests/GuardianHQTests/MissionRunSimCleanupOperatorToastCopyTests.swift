import XCTest

@testable import GuardianHQ

final class MissionRunSimCleanupOperatorToastCopyTests: XCTestCase {
    func test_partialFailureMessage_nilWhenClean() {
        XCTAssertNil(
            MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
                parkFailedCount: 0,
                shouldTeleport: true,
                rosterSnapshotCount: 1,
                rosterSkipped: 0,
                poolSnapshotCount: 0,
                poolSkipped: 0
            )
        )
    }

    func test_partialFailureMessage_parkOnly() {
        let m = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
            parkFailedCount: 2,
            shouldTeleport: false,
            rosterSnapshotCount: 0,
            rosterSkipped: 0,
            poolSnapshotCount: 0,
            poolSkipped: 0
        )
        XCTAssertTrue((m ?? "").contains("park did not finish for 2 vehicles"))
    }

    func test_partialFailureMessage_rosterSkips() {
        let m = MissionRunSimCleanupOperatorToastCopy.partialFailureMessage(
            parkFailedCount: 0,
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
            parkFailedCount: 1,
            shouldTeleport: true,
            rosterSnapshotCount: 1,
            rosterSkipped: 1,
            poolSnapshotCount: 1,
            poolSkipped: 2
        )
        let s = try XCTUnwrap(m)
        XCTAssertTrue(s.contains("park"))
        XCTAssertTrue(s.contains("roster"))
        XCTAssertTrue(s.contains("reserve pool"))
    }
}

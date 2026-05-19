import XCTest
@testable import GuardianHQ

final class WorldBuilderObstaclePersistenceTests: XCTestCase {
    func test_manifestAutosaveInterval_isSixtySeconds() {
        XCTAssertEqual(
            WorldBuilderObstaclePersistence.manifestAutosaveIntervalNs,
            60_000_000_000
        )
    }
}

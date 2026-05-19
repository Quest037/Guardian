import XCTest
@testable import GuardianHQ

final class WorldBuilderObstacleViewportSyncPolicyTests: XCTestCase {
    func test_acceptsViewportObstacleList_sameIDs() {
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.centerXM = 3
        let prior = [record]
        var moved = record
        moved.centerXM = 7
        XCTAssertTrue(
            WorldBuilderObstacleViewportSyncPolicy.acceptsViewportObstacleList(
                prior: prior,
                proposed: [moved]
            )
        )
    }

    func test_acceptsViewportObstacleList_rejectsAddedID() {
        let prior = [TrainingEnvironmentObstacleRecord.defaults(for: .cube)]
        var extra = TrainingEnvironmentObstacleRecord.defaults(for: .cylinder)
        extra.id = TrainingEnvironmentObstacleRecord.newID()
        XCTAssertFalse(
            WorldBuilderObstacleViewportSyncPolicy.acceptsViewportObstacleList(
                prior: prior,
                proposed: prior + [extra]
            )
        )
    }

    func test_acceptsViewportObstacleList_rejectsRemovedID() {
        let prior = [TrainingEnvironmentObstacleRecord.defaults(for: .cube)]
        XCTAssertFalse(
            WorldBuilderObstacleViewportSyncPolicy.acceptsViewportObstacleList(
                prior: prior,
                proposed: []
            )
        )
    }
}

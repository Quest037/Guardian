import XCTest
@testable import GuardianCore

final class WorldBuilderLiveObstacleSyncTests: XCTestCase {
    func test_obstacleIDsInSim_matchesModelNamesToManifestIds() {
        let a = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        var b = TrainingEnvironmentObstacleRecord.defaults(for: .cuboid)
        b.id = TrainingEnvironmentObstacleRecord.newID()
        let live = [
            TrainingEnvironmentObstacleNaming.modelName(obstacleID: a.id),
            "open_field_floor",
        ]
        let ids = WorldBuilderLiveObstacleSync.obstacleIDsInSim(manifest: [a, b], liveModelNames: live)
        XCTAssertEqual(ids, [a.id])
    }

    func test_gazeboModelName_resolvesFromLiveList() {
        let record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        let expected = TrainingEnvironmentObstacleNaming.modelName(obstacleID: record.id)
        let resolved = WorldBuilderLiveObstacleSync.gazeboModelName(
            for: record.id,
            in: [expected, "open_field_floor"]
        )
        XCTAssertEqual(resolved, expected)
    }
}

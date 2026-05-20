import XCTest
@testable import GuardianCore

final class WorldBuilderObstacleViewportSyncPolicyTests: XCTestCase {
    func test_mergingPoseUpdates_preservesManifestDimensions() {
        var manifest = TrainingEnvironmentObstacleRecord.defaults(for: .cuboid)
        manifest.id = "obstacle-a"
        manifest.setCuboidDimensions(lengthM: 100, widthM: 4, heightM: 6)
        manifest.centerXM = 10
        manifest.centerYM = 5

        var viewport = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        viewport.id = "obstacle-a"
        viewport.centerXM = 12
        viewport.centerYM = -3
        viewport.centerZM = 2
        viewport.yawDeg = 45

        let merged = WorldBuilderObstacleViewportSyncPolicy.mergingPoseUpdates(
            prior: [manifest],
            proposed: [viewport]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].kind, .cuboid)
        XCTAssertEqual(merged[0].cuboid?.lengthM, 100, accuracy: 0.001)
        XCTAssertEqual(merged[0].cuboid?.widthM, 4, accuracy: 0.001)
        XCTAssertEqual(merged[0].centerXM, 12, accuracy: 0.001)
        XCTAssertEqual(merged[0].centerYM, -3, accuracy: 0.001)
        XCTAssertEqual(merged[0].yawDeg, 45, accuracy: 0.001)
    }
}

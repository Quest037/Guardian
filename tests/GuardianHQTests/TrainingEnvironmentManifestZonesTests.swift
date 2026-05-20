import XCTest
@testable import GuardianCore

final class TrainingEnvironmentManifestZonesTests: XCTestCase {
    func test_hasConfiguredStartAndEndZones_requiresBoth() {
        let spawn = TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0)
        let goal = TrainingEnvironmentPose(xM: 10, yM: 0, zM: 0, yawDeg: 0)
        var manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: spawn,
            defaultGoal: goal
        )
        XCTAssertFalse(manifest.hasConfiguredStartAndEndZones)

        manifest.startZoneConfigured = true
        XCTAssertFalse(manifest.hasConfiguredStartAndEndZones)

        manifest.endZoneConfigured = true
        XCTAssertTrue(manifest.hasConfiguredStartAndEndZones)
    }
}

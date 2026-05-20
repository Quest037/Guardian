import XCTest
@testable import GuardianCore

final class TrainingEnvironmentSelectionPolicyTests: XCTestCase {
    func test_isSelectable_allowsIncompleteMapsWhileTemporaryBypassEnabled() {
        XCTAssertTrue(TrainingEnvironmentSelectionPolicy.allowsMapsWithoutStartAndEndZones)
        let spawn = TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0)
        let goal = TrainingEnvironmentPose(xM: 10, yM: 0, zM: 0, yawDeg: 0)
        var manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: spawn,
            defaultGoal: goal
        )
        XCTAssertFalse(manifest.hasConfiguredStartAndEndZones)
        XCTAssertTrue(TrainingEnvironmentSelectionPolicy.isSelectableForTrainingLab(manifest: manifest))

        manifest.startZoneConfigured = true
        manifest.endZoneConfigured = true
        XCTAssertTrue(TrainingEnvironmentSelectionPolicy.isSelectableForTrainingLab(manifest: manifest))
    }
}

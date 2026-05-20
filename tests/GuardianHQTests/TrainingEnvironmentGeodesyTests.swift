import XCTest
@testable import GuardianCore

final class TrainingEnvironmentGeodesyTests: XCTestCase {
    func test_mapSessionOrigin_anchorsAtManifestDefaultSpawn() {
        let fallback = SimSpawnDefaults(
            latitudeDeg: 47.397742,
            longitudeDeg: 8.545594,
            altitudeM: 0,
            headingDeg: 0,
            batteryPercent: 100,
            batteryVoltageV: 16,
            batteryCurrentA: 0
        )
        let manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: TrainingEnvironmentPose(xM: 12, yM: -8, zM: 0.1, yawDeg: 45),
            defaultGoal: TrainingEnvironmentPose(xM: 40, yM: 0, zM: 0.1, yawDeg: 0)
        )
        let origin = TrainingEnvironmentGeodesy.mapSessionOrigin(manifest: manifest, fallback: fallback)
        let expected = TrainingEnvironmentGeodesy.taskPose(
            environmentPose: manifest.defaultSpawn,
            origin: fallback
        )
        XCTAssertEqual(origin.latitudeDeg, expected.latitudeDeg, accuracy: 1e-6)
        XCTAssertEqual(origin.longitudeDeg, expected.longitudeDeg, accuracy: 1e-6)
        XCTAssertEqual(origin.altitudeM, expected.absoluteAltitudeM, accuracy: 1e-6)
        XCTAssertEqual(origin.headingDeg, 45)
    }
}

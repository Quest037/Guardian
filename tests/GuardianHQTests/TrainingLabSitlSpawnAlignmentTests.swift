import XCTest

@testable import GuardianCore

final class TrainingLabSitlSpawnAlignmentTests: XCTestCase {
    func test_sitlSpawnDefaults_matches_slot_task_pose() {
        let origin = SimSpawnDefaults(
            latitudeDeg: -35.0,
            longitudeDeg: 149.0,
            altitudeM: 580.0,
            headingDeg: 0
        )
        let env = TrainingEnvironmentPose(xM: 8, yM: -3, zM: 0.1, yawDeg: 90)
        let sitl = TrainingLabSitlSpawnAlignment.sitlSpawnDefaults(
            environmentPose: env,
            mapGeodeticOrigin: origin,
            batterySeed: .default
        )
        let task = TrainingEnvironmentGeodesy.taskPose(environmentPose: env, origin: origin)
        XCTAssertEqual(sitl.latitudeDeg, task.latitudeDeg, accuracy: 1e-6)
        XCTAssertEqual(sitl.longitudeDeg, task.longitudeDeg, accuracy: 1e-6)
        XCTAssertEqual(sitl.altitudeM, task.absoluteAltitudeM, accuracy: 1e-3)
        XCTAssertEqual(sitl.headingDeg, env.yawDeg, accuracy: 1e-3)
        XCTAssertEqual(sitl.batteryPercent, SimSpawnDefaults.default.batteryPercent)
    }

    func test_gazeboPlacement_pose_matches_environment_pose() {
        let worldID = UUID()
        let env = TrainingEnvironmentPose(xM: 2, yM: 4, zM: 0.2, yawDeg: 15)
        let placement = TrainingLabSitlSpawnAlignment.gazeboPlacement(
            worldID: worldID,
            environmentPose: env
        )
        XCTAssertEqual(placement.worldID, worldID)
        XCTAssertEqual(placement.pose, env)
    }

    @MainActor
    func test_pending_entry_pose_uses_start_zone_slot_not_manifest_spawn() {
        var manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0.1, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 40, yM: 0, zM: 0.1, yawDeg: 0),
            startZoneConfigured: true,
            endZoneConfigured: true
        )
        manifest.startZoneRadiusM = 20
        manifest.endZoneRadiusM = 20
        let pkg = TrainingEnvironmentPackage(
            manifest: manifest,
            packageRootURL: URL(fileURLWithPath: "/tmp"),
            source: .bundled
        )
        let origin = TrainingLabMapSessionLifecycle.mapGeodeticOrigin(
            environment: pkg,
            spawnDefaults: .default
        )
        let squad = TrainingLabSquad(
            primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled),
            startZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 12, centerYM: -4, headingDeg: 30)
        )
        let envPose = TrainingLabMapSessionLifecycle.startEnvironmentPoseForPendingEntry(
            squad: squad,
            squadIndex: 0,
            entryIndex: 0,
            environment: pkg,
            mapGeodeticOrigin: origin,
            learningSquadID: nil,
            learningSquadSingleVehicleStart: nil
        )
        XCTAssertEqual(envPose.xM, 12, accuracy: 0.5)
        XCTAssertEqual(envPose.yM, -4, accuracy: 0.5)
        XCTAssertNotEqual(envPose.xM, manifest.defaultSpawn.xM, accuracy: 0.01)
    }
}

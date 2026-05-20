import XCTest

@testable import GuardianHQ

final class TrainingLabMapSessionLifecycleTests: XCTestCase {
    func test_environment_geodesy_round_trip() {
        let origin = SimSpawnDefaults.default
        let env = TrainingEnvironmentPose(xM: 4, yM: -2, zM: 0.2, yawDeg: 45)
        let task = TrainingEnvironmentGeodesy.taskPose(environmentPose: env, origin: origin)
        let back = TrainingEnvironmentGeodesy.environmentPose(taskPose: task, origin: origin)
        XCTAssertEqual(back.xM, env.xM, accuracy: 0.01)
        XCTAssertEqual(back.yM, env.yM, accuracy: 0.01)
        XCTAssertEqual(back.zM, env.zM, accuracy: 0.01)
        XCTAssertEqual(back.yawDeg, env.yawDeg)
    }

    @MainActor
    func test_second_squad_primary_staggered_in_environment_frame() {
        let manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0.1, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 10, yM: 0, zM: 0.1, yawDeg: 0)
        )
        let pkg = TrainingEnvironmentPackage(
            manifest: manifest,
            packageRootURL: URL(fileURLWithPath: "/tmp"),
            source: .bundled
        )
        let squads = [
            TrainingLabSquad(primary: TrainingLabRosterEntry(vehicleClass: .ugvWheeled)),
            TrainingLabSquad(primary: TrainingLabRosterEntry(vehicleClass: .ugvTracked)),
        ]
        let poses = TrainingLabMapSessionLifecycle.resolveStartPoses(
            squads: squads,
            environment: pkg,
            spawnDefaults: .default,
            sitlInstances: [],
            learningSquadID: squads[0].id,
            learningSquadSingleVehicleStart: nil
        )
        XCTAssertTrue(poses.isEmpty)
    }
}

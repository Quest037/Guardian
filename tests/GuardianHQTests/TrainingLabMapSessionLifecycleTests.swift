import XCTest

@testable import GuardianCore

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
            mapGeodeticOrigin: .default,
            sitlInstances: [],
            learningSquadID: squads[0].id,
            learningSquadSingleVehicleStart: nil
        )
        XCTAssertTrue(poses.isEmpty)
    }

    @MainActor
    func test_resolveStartPoses_usesSlotNotTeachOverrideWhenStartZonePlaced() {
        let fallback = SimSpawnDefaults.default
        var manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0.1, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 50, yM: 0, zM: 0.1, yawDeg: 0),
            startZoneConfigured: true,
            endZoneConfigured: true
        )
        manifest.startZoneRadiusM = 25
        manifest.endZoneRadiusM = 25
        let pkg = TrainingEnvironmentPackage(
            manifest: manifest,
            packageRootURL: URL(fileURLWithPath: "/tmp"),
            source: .bundled
        )
        let mapOrigin = TrainingLabMapSessionLifecycle.mapGeodeticOrigin(
            environment: pkg,
            spawnDefaults: fallback
        )
        var primary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        primary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "v1",
            linkReady: true,
            preflightPassed: true
        )
        let squad = TrainingLabSquad(
            primary: primary,
            startZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: -5, centerYM: 3, headingDeg: 10)
        )
        let teachOverride = TrainingTaskPose(
            latitudeDeg: -35,
            longitudeDeg: 149,
            headingDeg: 0,
            absoluteAltitudeM: 0
        )
        let sitl = SitlRunningInstance(
            id: primary.slotState!.sitlSessionID,
            platform: .px4,
            preset: .ugvWheeled,
            stackInstanceIndex: 0,
            mavlinkIngressPort: 5000,
            mavlinkSystemID: 1,
            px4GcsUdpPort: 14540,
            isAlive: true,
            lastExitCode: nil,
            spawnOwner: .trainingRoster,
            startedAt: Date()
        )
        let poses = TrainingLabMapSessionLifecycle.resolveStartPoses(
            squads: [squad],
            environment: pkg,
            mapGeodeticOrigin: mapOrigin,
            sitlInstances: [sitl],
            learningSquadID: squad.id,
            learningSquadSingleVehicleStart: teachOverride
        )
        XCTAssertEqual(poses.count, 1)
        XCTAssertEqual(poses[0].environmentPose.xM, squad.startZoneAnchor!.centerXM, accuracy: 0.5)
        XCTAssertEqual(poses[0].environmentPose.yM, squad.startZoneAnchor!.centerYM, accuracy: 0.5)
        XCTAssertNotEqual(poses[0].taskPose.latitudeDeg, teachOverride.latitudeDeg, accuracy: 0.001)
    }
}

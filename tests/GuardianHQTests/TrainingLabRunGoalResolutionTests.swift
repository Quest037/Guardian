import XCTest
@testable import GuardianCore

final class TrainingLabRunGoalResolutionTests: XCTestCase {

    func test_buildSessionPlan_singleLearningSquad_resolvesStartAndEnd() {
        var primary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        primary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "training-1",
            linkReady: true,
            preflightPassed: true
        )
        let squadID = UUID()
        let squad = TrainingLabSquad(
            id: squadID,
            primary: primary,
            startZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: -10, centerYM: 0, headingDeg: 0),
            endZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 40, centerYM: 0, headingDeg: 90)
        )
        let zones = WorldBuilderZonesSnapshot(
            start: WorldBuilderZoneState(
                placed: true,
                centerXM: 0,
                centerYM: 0,
                centerZM: 0,
                radiusM: 30,
                shape: .circle
            ),
            end: WorldBuilderZoneState(
                placed: true,
                centerXM: 50,
                centerYM: 0,
                centerZM: 0,
                radiusM: 30,
                shape: .circle
            )
        )
        let manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 10, yM: 0, zM: 0, yawDeg: 0)
        )
        let pkg = TrainingEnvironmentPackage(
            manifest: manifest,
            packageRootURL: URL(fileURLWithPath: "/tmp"),
            source: .bundled
        )
        let spawn = SimSpawnDefaults(
            latitudeDeg: -35,
            longitudeDeg: 149,
            altitudeM: 10,
            headingDeg: 0
        )

        let mapOrigin = TrainingEnvironmentGeodesy.mapSessionOrigin(manifest: manifest, fallback: spawn)
        let build = TrainingLabRunGoalResolution.buildSessionPlan(
            squads: [squad],
            zones: zones,
            environment: pkg,
            mapGeodeticOrigin: mapOrigin,
            learningSquadID: squadID
        )

        XCTAssertTrue(build.isReady)
        XCTAssertEqual(build.plans?.vehiclePlans.count, 1)
        let plan = build.plans?.vehiclePlans.first
        XCTAssertEqual(plan?.role, .learning)
        XCTAssertEqual(plan?.vehicleID, "training-1")
        let distM = MissionTelemetryGeo.horizontalDistanceM(
            lat1: plan!.layout.start.latitudeDeg,
            lon1: plan!.layout.start.longitudeDeg,
            lat2: plan!.layout.goal.latitudeDeg,
            lon2: plan!.layout.goal.longitudeDeg
        )
        XCTAssertGreaterThan(distM, 30)
        XCTAssertFalse(plan!.requiresStrictEndSlotBox)
    }

    func test_buildSessionPlan_strictEndSlot_whenEndFormationExplicit() {
        var primary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        primary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "training-1",
            linkReady: true,
            preflightPassed: true
        )
        var policy = TrainingLabSquadFormationPolicy.default
        policy.endFormation = .chevron
        let squad = TrainingLabSquad(
            primary: primary,
            formationPolicy: policy,
            startZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 0, centerYM: 0, headingDeg: 0),
            endZoneAnchor: TrainingLabZoneFormationAnchor(centerXM: 20, centerYM: 0, headingDeg: 0)
        )
        let zones = WorldBuilderZonesSnapshot(
            start: WorldBuilderZoneState(
                placed: true, centerXM: 0, centerYM: 0, centerZM: 0, radiusM: 30, shape: .circle
            ),
            end: WorldBuilderZoneState(
                placed: true, centerXM: 30, centerYM: 0, centerZM: 0, radiusM: 30, shape: .circle
            )
        )
        let manifest = TrainingEnvironmentManifest(
            id: "test",
            displayName: "Test",
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 10, yM: 0, zM: 0, yawDeg: 0),
            startZoneConfigured: true,
            endZoneConfigured: true
        )
        let pkg = TrainingEnvironmentPackage(
            manifest: manifest,
            packageRootURL: URL(fileURLWithPath: "/tmp"),
            source: .bundled
        )
        let build = TrainingLabRunGoalResolution.buildSessionPlan(
            squads: [squad],
            zones: zones,
            environment: pkg,
            mapGeodeticOrigin: .default,
            learningSquadID: squad.id
        )
        XCTAssertTrue(build.isReady)
        XCTAssertTrue(build.plans?.vehiclePlans.first?.requiresStrictEndSlotBox == true)
    }

    func test_buildSessionPlan_rejectsWingmenSquad() {
        var primary = TrainingLabRosterEntry(vehicleClass: .ugvWheeled)
        primary.slotState = FormationsPlaygroundSlotState(
            sitlSessionID: UUID(),
            vehicleID: "v1",
            linkReady: true,
            preflightPassed: true
        )
        let squad = TrainingLabSquad(
            primary: primary,
            wingmen: [TrainingLabRosterEntry(vehicleClass: .ugvWheeled)]
        )
        let zones = WorldBuilderZonesSnapshot(
            start: WorldBuilderZoneState(
                placed: true,
                centerXM: 0,
                centerYM: 0,
                centerZM: 0,
                radiusM: 20,
                shape: .circle
            ),
            end: WorldBuilderZoneState(
                placed: true,
                centerXM: 40,
                centerYM: 0,
                centerZM: 0,
                radiusM: 20,
                shape: .circle
            )
        )
        let manifest = TrainingEnvironmentManifest(
            id: "t",
            displayName: "T",
            defaultSpawn: TrainingEnvironmentPose(),
            defaultGoal: TrainingEnvironmentPose()
        )
        let pkg = TrainingEnvironmentPackage(
            manifest: manifest,
            packageRootURL: URL(fileURLWithPath: "/tmp"),
            source: .bundled
        )
        let mapOrigin = TrainingEnvironmentGeodesy.mapSessionOrigin(
            manifest: manifest,
            fallback: SimSpawnDefaults.default
        )
        let build = TrainingLabRunGoalResolution.buildSessionPlan(
            squads: [squad],
            zones: zones,
            environment: pkg,
            mapGeodeticOrigin: mapOrigin,
            learningSquadID: nil
        )
        XCTAssertFalse(build.isReady)
        XCTAssertTrue(build.issues.contains(where: { $0.message.contains("wingmen") }))
    }
}

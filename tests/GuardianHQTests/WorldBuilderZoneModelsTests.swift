import XCTest
@testable import GuardianHQ

final class WorldBuilderZoneModelsTests: XCTestCase {
    func test_manifest_zone_fields_roundTrip() throws {
        var manifest = TrainingEnvironmentManifest(
            id: "zone-test",
            displayName: "Zone test",
            defaultSpawn: TrainingEnvironmentPose(xM: 1, yM: 2, zM: 0.1, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 9, yM: 4, zM: 0.2, yawDeg: 0),
            startZoneRadiusM: 30,
            endZoneRadiusM: 45,
            startZoneShape: TrainingEnvironmentZoneShape.circle.rawValue,
            endZoneShape: TrainingEnvironmentZoneShape.square.rawValue,
            startZoneConfigured: true,
            endZoneConfigured: true
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TrainingEnvironmentManifest.self, from: data)
        XCTAssertEqual(decoded.startZoneRadiusM, 30)
        XCTAssertEqual(decoded.endZoneRadiusM, 45)
        XCTAssertEqual(decoded.startZoneShape, TrainingEnvironmentZoneShape.circle.rawValue)
        XCTAssertEqual(decoded.endZoneShape, TrainingEnvironmentZoneShape.square.rawValue)
        XCTAssertTrue(decoded.startZoneConfigured)
        XCTAssertTrue(decoded.endZoneConfigured)

        let zones = WorldBuilderZoneManifestSupport.zones(from: decoded)
        XCTAssertTrue(zones.start.placed)
        XCTAssertEqual(zones.start.centerXM, 1)
        XCTAssertEqual(zones.end.shape, .square)
        XCTAssertEqual(zones.end.radiusM, 45)

        WorldBuilderZoneManifestSupport.apply(zones, to: &manifest)
        XCTAssertEqual(manifest.defaultSpawn.xM, 1)
        XCTAssertEqual(manifest.defaultGoal.yM, 4)
    }

    func test_fitsOnFloor_circleCenterInsideButEdgeOutside() {
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 50)
        let zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: 55,
            shape: .circle
        )
        XCTAssertFalse(WorldBuilderZoneBoundsCheck.fitsOnFloor(zone, floor: floor))
    }

    func test_snapZoneToFloor_translatesCircleToMapEdge() {
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 50)
        var zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 48,
            centerYM: 0,
            centerZM: 0,
            radiusM: 30,
            shape: .circle
        )
        XCTAssertTrue(WorldBuilderZoneBoundsCheck.snapZoneToFloor(&zone, floor: floor))
        XCTAssertTrue(WorldBuilderZoneBoundsCheck.fitsOnFloor(zone, floor: floor))
        XCTAssertEqual(zone.centerXM, 20, accuracy: 1e-4)
    }

    func test_snapZoneToFloor_shrinksRadiusWhenTranslationNotEnough() {
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 50)
        var zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: 55,
            shape: .circle
        )
        XCTAssertTrue(WorldBuilderZoneBoundsCheck.snapZoneToFloor(&zone, floor: floor))
        XCTAssertTrue(WorldBuilderZoneBoundsCheck.fitsOnFloor(zone, floor: floor))
        XCTAssertEqual(zone.radiusM, 50, accuracy: 1e-4)
    }

    func test_snapZoneToFloor_failsWhenMinimumRadiusCannotFit() {
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 8)
        var zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 0,
            centerYM: 0,
            centerZM: 0,
            radiusM: 30,
            shape: .circle
        )
        XCTAssertFalse(WorldBuilderZoneBoundsCheck.snapZoneToFloor(&zone, floor: floor))
    }

    func test_snapZoneToFloor_squareCornerSnapsInward() {
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 50)
        var zone = WorldBuilderZoneState(
            placed: true,
            centerXM: 40,
            centerYM: 40,
            centerZM: 0,
            radiusM: 20,
            shape: .square
        )
        XCTAssertTrue(WorldBuilderZoneBoundsCheck.snapZoneToFloor(&zone, floor: floor))
        XCTAssertTrue(WorldBuilderZoneBoundsCheck.fitsOnFloor(zone, floor: floor))
        XCTAssertEqual(zone.centerXM, 30, accuracy: 1e-4)
        XCTAssertEqual(zone.centerYM, 30, accuracy: 1e-4)
    }

    func test_apply_clearsConfiguredWhenZoneUnplaced() {
        var manifest = TrainingEnvironmentManifest(
            id: "zone-clear",
            displayName: "Clear",
            defaultSpawn: TrainingEnvironmentPose(xM: 1, yM: 2, zM: 0, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 3, yM: 4, zM: 0, yawDeg: 0),
            startZoneConfigured: true,
            endZoneConfigured: true
        )
        var zones = WorldBuilderZoneManifestSupport.zones(from: manifest)
        zones.start = .unplaced(shape: .circle)
        zones.end = WorldBuilderZoneState(
            placed: true,
            centerXM: 3,
            centerYM: 4,
            centerZM: 0,
            radiusM: 30,
            shape: .circle
        )
        WorldBuilderZoneManifestSupport.apply(zones, to: &manifest)
        XCTAssertFalse(manifest.startZoneConfigured)
        XCTAssertTrue(manifest.endZoneConfigured)
    }

    func test_clampZoneRadiiToAllowedRange_clampsToMinMax() {
        var zones = WorldBuilderZonesSnapshot(
            start: WorldBuilderZoneState(
                placed: false,
                centerXM: 0,
                centerYM: 0,
                centerZM: 0,
                radiusM: 12,
                shape: .circle
            ),
            end: .unplaced()
        )
        WorldBuilderZoneManifestSupport.clampZoneRadiiToAllowedRange(&zones)
        XCTAssertEqual(zones.start.radiusM, WorldBuilderZoneState.minRadiusM)
    }

    func test_manifest_decodesMissingZoneFieldsWithDefaults() throws {
        let json = """
        {
          "formatVersion": 1,
          "id": "legacy",
          "displayName": "Legacy",
          "worldFile": "world.sdf",
          "defaultSpawn": { "xM": 0, "yM": 0, "zM": 0, "yawDeg": 0 },
          "defaultGoal": { "xM": 1, "yM": 0, "zM": 0, "yawDeg": 0 }
        }
        """
        let decoded = try JSONDecoder().decode(
            TrainingEnvironmentManifest.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(decoded.startZoneRadiusM, WorldBuilderZoneState.defaultRadiusM)
        XCTAssertFalse(decoded.startZoneConfigured)
        XCTAssertEqual(decoded.startZoneShape, TrainingEnvironmentZoneShape.circle.rawValue)
    }
}

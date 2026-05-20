import XCTest
@testable import GuardianHQ

final class TrainingEnvironmentObstacleTests: XCTestCase {
    func test_newDraftManifest_hasNoDefaultObstacles() {
        let manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        XCTAssertTrue(manifest.obstacles.isEmpty)
    }

    func test_manifestRoundTrip_obstacles() throws {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.centerXM = 12
        record.centerYM = -4
        manifest.obstacles = [record]

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TrainingEnvironmentManifest.self, from: data)
        XCTAssertEqual(decoded.obstacles.count, 1)
        XCTAssertEqual(decoded.obstacles[0].kind, .cube)
        XCTAssertEqual(decoded.obstacles[0].centerXM, 12, accuracy: 0.001)
    }

    func test_clampToFloor_keepsFootprintInside() {
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.centerXM = 90
        record.centerYM = 0
        WorldBuilderObstacleManifestSupport.clampToFloor(&record, floorHalfM: 50)
        let (hx, _) = WorldBuilderObstacleManifestSupport.footprintHalfExtents(
            record: record,
            yawRad: 0
        )
        XCTAssertLessThanOrEqual(abs(record.centerXM) + hx, 50 + 0.01)
    }

    func test_worldComposer_writesObstacleModel() throws {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        manifest.floorSize = TrainingEnvironmentFloorSize.micro.rawValue
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cylinder)
        record.centerXM = 5
        record.centerYM = -3
        record.centerZM = 1.5
        record.usesAutoZ = false
        manifest.obstacles = [record]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-obstacle-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let worldURL = dir.appendingPathComponent("world.sdf")
        try TrainingEnvironmentWorldComposer.writeWorld(
            manifest: manifest,
            to: worldURL,
            mode: .trainingRun
        )
        let xml = try String(contentsOf: worldURL, encoding: .utf8)
        XCTAssertTrue(xml.contains(TrainingEnvironmentObstacleBaking.bakedModelName))
        XCTAssertTrue(xml.contains("<cylinder>"))
        XCTAssertTrue(xml.contains("open_field_floor"))
    }

    func test_validateManifest_rejectsTooManyObstacles() {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        manifest.obstacles = (0..<101).map { _ in TrainingEnvironmentObstacleRecord.defaults(for: .cube) }
        XCTAssertThrowsError(try TrainingEnvironmentAuthoring.validateManifest(manifest)) { error in
            guard case TrainingEnvironmentAuthoringError.tooManyObstacles = error else {
                return XCTFail("Expected tooManyObstacles, got \(error)")
            }
        }
    }

    func test_snapObstacleToFloor_translatesWithoutFailedWhenFits() {
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.centerXM = 10
        record.centerYM = 0
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 50)
        let ok = WorldBuilderObstacleBoundsCheck.snapObstacleToFloor(&record, floor: floor)
        XCTAssertTrue(ok)
        XCTAssertTrue(WorldBuilderObstacleBoundsCheck.fitsOnFloor(record, floor: floor))
    }

    func test_obstaclesEditorSnapshot_encodesDeletingID() throws {
        let snapshot = WorldBuilderObstaclesEditorSnapshot.make(
            editorActive: true,
            selectedID: nil,
            placementActive: false,
            draft: TrainingEnvironmentObstacleRecord.defaults(for: .cube),
            obstacles: [],
            mapHalfExtentM: 50,
            deletingID: "abc-123"
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WorldBuilderObstaclesEditorSnapshot.self, from: data)
        XCTAssertEqual(decoded.deletingID, "abc-123")
    }

    func test_obstacleNaming_matchesLiveModelName() {
        let id = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let expected = TrainingEnvironmentObstacleNaming.modelName(obstacleID: id)
        XCTAssertTrue(TrainingEnvironmentObstacleNaming.matchesModelName(expected, obstacleID: id))
        XCTAssertFalse(TrainingEnvironmentObstacleNaming.matchesModelName("open_field_floor", obstacleID: id))
    }

    func test_clampFootZM_respectsLimits() {
        let scene: TrainingEnvironmentSceneType = .flat
        let floorSideM = 1000.0
        let limits = WorldBuilderObstacleManifestSupport.footZLimitsM(
            sceneType: scene,
            floorSideM: floorSideM
        )
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.usesAutoZ = false
        let halfHeight = record.verticalExtentsM().dz / 2
        WorldBuilderObstacleManifestSupport.setFootZM(3000, record: &record)
        WorldBuilderObstacleManifestSupport.clampFootZM(
            &record,
            sceneType: scene,
            floorSideM: floorSideM
        )
        XCTAssertEqual(WorldBuilderObstacleManifestSupport.footZM(for: record), limits.max, accuracy: 0.001)
        XCTAssertEqual(record.centerZM, limits.max + halfHeight, accuracy: 0.001)
        WorldBuilderObstacleManifestSupport.setFootZM(-800, record: &record)
        WorldBuilderObstacleManifestSupport.clampFootZM(
            &record,
            sceneType: scene,
            floorSideM: floorSideM
        )
        XCTAssertEqual(WorldBuilderObstacleManifestSupport.footZM(for: record), limits.min, accuracy: 0.001)
    }

    func test_flatFootZLimits_matchMapBaseDepth() {
        let limits = WorldBuilderObstacleManifestSupport.footZLimitsM(
            sceneType: .flat,
            floorSideM: 1000
        )
        XCTAssertEqual(limits.min, -TrainingEnvironmentWorldSDF.openFieldFloorDepthM, accuracy: 0.001)
        XCTAssertEqual(limits.max, 0, accuracy: 0.001)
    }

    func test_resizePreservesManualFootZ() {
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.usesAutoZ = false
        WorldBuilderObstacleManifestSupport.setFootZM(-2, record: &record)
        let footBefore = WorldBuilderObstacleManifestSupport.footZM(for: record)
        record.setEdgeM(6)
        WorldBuilderObstacleManifestSupport.normalizeRecord(
            &record,
            floorHalfM: 50,
            sceneType: .flat
        )
        XCTAssertEqual(WorldBuilderObstacleManifestSupport.footZM(for: record), footBefore, accuracy: 0.001)
    }

    func test_snapObstacleToFloor_failedWhenFootprintLargerThanMap() {
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.setEdgeM(120)
        record.centerXM = 0
        record.centerYM = 0
        let floor = WorldBuilderZoneFloorRect.centeredSquare(halfExtentM: 50)
        let ok = WorldBuilderObstacleBoundsCheck.snapObstacleToFloor(&record, floor: floor)
        XCTAssertFalse(ok)
    }
}

import XCTest
@testable import GuardianCore

final class TrainingEnvironmentAuthoringTests: XCTestCase {
    func test_newDraftID_slugifiesDisplayName() {
        let id = TrainingEnvironmentAuthoring.newDraftID(from: "UGV Slope Course 1")
        XCTAssertEqual(id, "ugv-slope-course-1")
    }

    func test_uniqueEnvironmentID_appendsTickerWhenOccupied() {
        let occupied: Set<String> = ["open-field", "open-field-2"]
        let id = TrainingEnvironmentAuthoring.uniqueEnvironmentID(slug: "open-field", occupiedIDs: occupied)
        XCTAssertEqual(id, "open-field-3")
    }

    func test_uniqueEnvironmentID_returnsBaseWhenFree() {
        let id = TrainingEnvironmentAuthoring.uniqueEnvironmentID(
            slug: "My Park",
            occupiedIDs: ["other-world"]
        )
        XCTAssertEqual(id, "my-park")
    }

    func test_uniqueEnvironmentID_duplicateCopySlug() {
        let occupied: Set<String> = ["ugv-course", "ugv-course-copy"]
        let id = TrainingEnvironmentAuthoring.uniqueEnvironmentID(
            slug: TrainingEnvironmentAuthoring.slugFromDisplayName("UGV Course copy"),
            occupiedIDs: occupied
        )
        XCTAssertEqual(id, "ugv-course-copy-2")
    }

    func test_validateManifest_rejectsEmptyDisplayName() {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        manifest.displayName = "   "
        XCTAssertThrowsError(try TrainingEnvironmentAuthoring.validateManifest(manifest))
    }

    func test_validateManifest_rejectsAnchorOutOfRange() {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        manifest.defaultGoal.xM = 9999
        XCTAssertThrowsError(try TrainingEnvironmentAuthoring.validateManifest(manifest))
    }

    func test_floorSize_sideLengths() {
        XCTAssertEqual(TrainingEnvironmentFloorSize.micro.floorSideM, 100, accuracy: 0.001)
        XCTAssertEqual(TrainingEnvironmentFloorSize.mini.floorSideM, 500, accuracy: 0.001)
        XCTAssertEqual(TrainingEnvironmentFloorSize.small.floorSideM, 1000, accuracy: 0.001)
        XCTAssertEqual(TrainingEnvironmentFloorSize.medium.floorSideM, 1000 * sqrt(2), accuracy: 0.001)
        XCTAssertEqual(TrainingEnvironmentFloorSize.large.floorSideM, 2000, accuracy: 0.001)
    }

    func test_floorSize_orbitMinDistance() {
        XCTAssertEqual(TrainingEnvironmentFloorSize.micro.orbitMinDistanceM, 1, accuracy: 0.001)
        XCTAssertEqual(TrainingEnvironmentFloorSize.mini.orbitMinDistanceM, 50, accuracy: 0.001)
        XCTAssertEqual(TrainingEnvironmentFloorSize.small.orbitMinDistanceM, 50, accuracy: 0.001)
    }

    func test_parseOpenFieldFloorSideM_fromMicroWorld() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-micro-floor-\(UUID().uuidString).sdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try TrainingEnvironmentWorldSDF.writeOpenFieldWorld(to: url, floorSideM: 100)
        XCTAssertEqual(TrainingEnvironmentWorldSDF.parseOpenFieldFloorSideM(from: url), 100, accuracy: 0.001)
    }

    func test_floorSizeLabel_resolvesMicroSideLength() {
        XCTAssertEqual(
            TrainingEnvironmentFloorSize.resolved(from: "micro").floorSideM,
            100,
            accuracy: 0.001
        )
    }

    func test_writeOpenFieldWorld_embedsFloorSize() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-test-world-\(UUID().uuidString).sdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try TrainingEnvironmentWorldSDF.writeOpenFieldWorld(to: url, floorSideM: 2000)
        let xml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(xml.contains("<size>2000 2000 4</size>"))
        XCTAssertEqual(TrainingEnvironmentWorldSDF.openFieldFloorDepthM, 10, accuracy: 0.001)
        XCTAssertTrue(xml.contains("visual_top"))
        XCTAssertTrue(xml.contains("visual_bottom"))
        XCTAssertTrue(xml.contains(TrainingEnvironmentWorldSDF.OpenFieldFloorColors.topDiffuse))
        XCTAssertTrue(xml.contains(TrainingEnvironmentWorldSDF.OpenFieldFloorColors.bottomDiffuse))
        XCTAssertEqual(
            TrainingEnvironmentWorldSDF.parseWorldName(fromSDFXML: xml),
            TrainingEnvironmentWorldSDF.defaultWorldName
        )
    }

    func test_parseWorldName_readsFirstWorldElement() {
        let xml = #"<?xml version="1.0"?><sdf><world name="basic_test"></world></sdf>"#
        XCTAssertEqual(TrainingEnvironmentWorldSDF.parseWorldName(fromSDFXML: xml), "basic_test")
    }

    func test_manifest_decodesMissingSceneTypeAsFlat() throws {
        let json = """
        {
          "formatVersion": 1,
          "id": "test-world",
          "displayName": "Test",
          "description": "",
          "worldFile": "world.sdf",
          "tags": [],
          "floorSize": "small",
          "defaultSpawn": { "xM": 0, "yM": 0, "zM": 0, "yawDeg": 0 },
          "defaultGoal": { "xM": 1, "yM": 0, "zM": 0, "yawDeg": 0 }
        }
        """
        let manifest = try JSONDecoder().decode(TrainingEnvironmentManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.sceneType, TrainingEnvironmentSceneType.flat.rawValue)
    }

    func test_manifest_decodesMissingFloorSizeAsSmall() throws {
        let json = """
        {
          "formatVersion": 1,
          "id": "test-world",
          "displayName": "Test",
          "description": "",
          "worldFile": "world.sdf",
          "tags": [],
          "defaultSpawn": { "xM": 0, "yM": 0, "zM": 0, "yawDeg": 0 },
          "defaultGoal": { "xM": 1, "yM": 0, "zM": 0, "yawDeg": 0 }
        }
        """
        let manifest = try JSONDecoder().decode(TrainingEnvironmentManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.floorSize, TrainingEnvironmentFloorSize.small.rawValue)
    }
}

import XCTest
@testable import GuardianHQ

final class TrainingEnvironmentObstacleBakingTests: XCTestCase {
    func test_bakedModelXML_singleCube() throws {
        var record = TrainingEnvironmentObstacleRecord.defaults(for: .cube)
        record.centerXM = 4
        record.centerYM = -2
        record.centerZM = 1
        record.usesAutoZ = false

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-bake-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let xml = try TrainingEnvironmentObstacleBaking.bakedModelXML(records: [record], meshDirectory: dir)
        XCTAssertTrue(xml.contains(TrainingEnvironmentObstacleBaking.bakedModelName))
        XCTAssertTrue(xml.contains("<collision name=\"collision_0\">"))
        XCTAssertTrue(xml.contains(TrainingEnvironmentObstacleBaking.bakedVisualOBJFileName))
        let objURL = dir.appendingPathComponent(TrainingEnvironmentObstacleBaking.bakedVisualOBJFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: objURL.path))
    }

    func test_writeWorld_trainingRun_embedsBakedModel() throws {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        manifest.floorSize = TrainingEnvironmentFloorSize.micro.rawValue
        manifest.obstacles = [TrainingEnvironmentObstacleRecord.defaults(for: .cube)]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-bake-world-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let worldURL = dir.appendingPathComponent("world.sdf")
        try TrainingEnvironmentWorldComposer.writeWorld(
            manifest: manifest,
            to: worldURL,
            mode: .trainingRun
        )
        let text = try String(contentsOf: worldURL, encoding: .utf8)
        XCTAssertTrue(text.contains(TrainingEnvironmentObstacleBaking.bakedModelName))
        XCTAssertFalse(text.contains("guardian_obstacle_\(TrainingEnvironmentObstacleNaming.sanitizedIDSuffix(manifest.obstacles[0].id))"))
    }

    func test_writeWorld_builderSession_floorOnly() throws {
        var manifest = TrainingEnvironmentAuthoring.newDraftManifest()
        manifest.obstacles = [TrainingEnvironmentObstacleRecord.defaults(for: .cube)]

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-builder-world-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let worldURL = dir.appendingPathComponent("world.sdf")
        try TrainingEnvironmentWorldComposer.writeWorld(
            manifest: manifest,
            to: worldURL,
            mode: .builderSession
        )
        let names = WorldBuilderWorldSDFObstacles.obstacleModelNames(inWorldSDF: worldURL)
        XCTAssertTrue(names.isEmpty)
        XCTAssertFalse(WorldBuilderWorldSDFObstacles.includesBakedObstacleModel(inWorldSDF: worldURL))
    }
}

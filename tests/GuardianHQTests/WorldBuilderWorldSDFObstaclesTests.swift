import XCTest
@testable import GuardianHQ

final class WorldBuilderWorldSDFObstaclesTests: XCTestCase {
    func test_obstacleModelNames_parsesEmbeddedModels() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-sdf-obstacles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let worldURL = dir.appendingPathComponent("world.sdf")
        let xml = """
        <model name="guardian_obstacle_deadbeef">
          <static>true</static>
        </model>
        <model name='guardian_obstacle_cafebabe'>
          <static>true</static>
        </model>
        """
        try xml.write(to: worldURL, atomically: true, encoding: .utf8)

        let names = WorldBuilderWorldSDFObstacles.obstacleModelNames(inWorldSDF: worldURL)
        XCTAssertEqual(
            names,
            ["guardian_obstacle_deadbeef", "guardian_obstacle_cafebabe"]
        )
    }
}

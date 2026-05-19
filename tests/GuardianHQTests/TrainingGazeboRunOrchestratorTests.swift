import XCTest
@testable import GuardianHQ

final class TrainingGazeboRunOrchestratorTests: XCTestCase {
  func test_spawnPlan_usesRunPurposeAndWorldPath() throws {
    let root = try makeTempPackageRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let manifest = TrainingEnvironmentManifest(
      id: "test-yard",
      displayName: "Test yard",
      defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0.1, yawDeg: 0),
      defaultGoal: TrainingEnvironmentPose(xM: 4, yM: 2, zM: 0.1, yawDeg: 45)
    )
    let world = root.appendingPathComponent("world.sdf")
    try "<sdf version=\"1.9\"><world name=\"t\"></world></sdf>"
      .write(to: world, atomically: true, encoding: .utf8)
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)

    let pkg = TrainingEnvironmentPackage(
      manifest: manifest,
      packageRootURL: root,
      source: .user
    )
    let plan = TrainingGazeboRunOrchestrator.spawnPlan(for: pkg)
    XCTAssertEqual(plan.purpose, .run)
    XCTAssertEqual(plan.environmentID, "test-yard")
    XCTAssertEqual(plan.worldPath, world.path)
  }

  func test_environmentGeodesy_mapsEastNorthOffsets() {
    let origin = SimSpawnDefaults(
      latitudeDeg: 37.0,
      longitudeDeg: -122.0,
      altitudeM: 10,
      headingDeg: 0
    )
    let pose = TrainingEnvironmentGeodesy.taskPose(
      environmentPose: TrainingEnvironmentPose(xM: 100, yM: 50, zM: 0.5, yawDeg: 90),
      origin: origin
    )
    XCTAssertGreaterThan(pose.latitudeDeg, origin.latitudeDeg)
    XCTAssertGreaterThan(pose.longitudeDeg, origin.longitudeDeg)
    XCTAssertEqual(pose.absoluteAltitudeM, 10.5, accuracy: 0.001)
    XCTAssertEqual(pose.headingDeg, 90)
  }

  func test_layout_usesManifestSpawnAndTargetSlot() {
    let origin = SimSpawnDefaults(
      latitudeDeg: 37.0,
      longitudeDeg: -122.0,
      altitudeM: 10,
      headingDeg: 0
    )
    let manifest = TrainingEnvironmentManifest(
      id: "lot",
      displayName: "Lot",
      defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
      defaultGoal: TrainingEnvironmentPose(xM: 8, yM: 0, zM: 0, yawDeg: 0)
    )
    let pkg = TrainingEnvironmentPackage(
      manifest: manifest,
      packageRootURL: URL(fileURLWithPath: "/tmp/unused"),
      source: .bundled
    )
    let goal = TrainingEnvironmentGeodesy.taskPose(
      environmentPose: manifest.defaultGoal,
      origin: origin
    )
    let layout = TrainingGazeboRunOrchestrator.layout(
      environment: pkg,
      targetSlot: goal,
      spawnDefaults: origin
    )
    XCTAssertEqual(layout.start.latitudeDeg, origin.latitudeDeg, accuracy: 1e-9)
    XCTAssertEqual(layout.goal.latitudeDeg, goal.latitudeDeg, accuracy: 1e-9)
  }

  private func makeTempPackageRoot() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("guardian-gazebo-plan-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}

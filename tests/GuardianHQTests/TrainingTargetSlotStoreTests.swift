import XCTest
@testable import GuardianHQ

final class TrainingTargetSlotStoreTests: XCTestCase {
  func test_perEnvironmentRoundTrip() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("guardian-slot-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let poseA = TrainingTaskPose(
      latitudeDeg: 1,
      longitudeDeg: 2,
      headingDeg: 3,
      absoluteAltitudeM: 4
    )
    let poseB = TrainingTaskPose(
      latitudeDeg: 5,
      longitudeDeg: 6,
      headingDeg: 7,
      absoluteAltitudeM: 8
    )
    try TrainingTargetSlotStore.save(poseA, environmentID: "env-a", fileURL: dir)
    try TrainingTargetSlotStore.save(poseB, environmentID: "env-b", fileURL: dir)

    XCTAssertEqual(try TrainingTargetSlotStore.load(environmentID: "env-a", fileURL: dir), poseA)
    XCTAssertEqual(try TrainingTargetSlotStore.load(environmentID: "env-b", fileURL: dir), poseB)
    XCTAssertNil(try TrainingTargetSlotStore.load(environmentID: "missing", fileURL: dir))
  }

  func test_migratesLegacySinglePoseFile() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("guardian-slot-legacy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let legacy = TrainingTaskPose(
      latitudeDeg: 10,
      longitudeDeg: 20,
      headingDeg: 30,
      absoluteAltitudeM: 40
    )
    let legacyURL = dir.appendingPathComponent("training_target_slot.json")
    try JSONEncoder().encode(legacy).write(to: legacyURL, options: .atomic)

    let loaded = try TrainingTargetSlotStore.load(
      environmentID: TrainingEnvironmentManifest.defaultBundledID,
      fileURL: dir
    )
    XCTAssertEqual(loaded, legacy)
  }
}

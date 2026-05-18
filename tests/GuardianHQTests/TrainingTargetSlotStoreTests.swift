import XCTest
@testable import GuardianHQ

final class TrainingTargetSlotStoreTests: XCTestCase {
    func test_saveAndLoad_roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("slot.json")

        let pose = TrainingTaskPose(
            latitudeDeg: -35.1,
            longitudeDeg: 149.2,
            headingDeg: 42,
            absoluteAltitudeM: 12
        )
        try TrainingTargetSlotStore.save(pose, fileURL: fileURL)
        let loaded = try TrainingTargetSlotStore.load(fileURL: fileURL)
        XCTAssertEqual(loaded, pose)
    }

    func test_load_missingFile_returnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")
        XCTAssertNil(try TrainingTargetSlotStore.load(fileURL: url))
    }
}

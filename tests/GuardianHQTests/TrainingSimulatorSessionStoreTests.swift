import XCTest
@testable import GuardianCore

final class TrainingSimulatorSessionStoreTests: XCTestCase {
    func test_saveAndLoad_roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("session.json")

        let id = UUID()
        try TrainingSimulatorSessionStore.save(id, fileURL: fileURL)
        let loaded = try TrainingSimulatorSessionStore.load(fileURL: fileURL)
        XCTAssertEqual(loaded?.sitlSessionID, id)
    }

    func test_clear_removesRecord() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("session.json")

        try TrainingSimulatorSessionStore.save(UUID(), fileURL: fileURL)
        try TrainingSimulatorSessionStore.clear(fileURL: fileURL)
        XCTAssertNil(try TrainingSimulatorSessionStore.load(fileURL: fileURL))
    }

    func test_load_missingFile_returnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.json")
        XCTAssertNil(try TrainingSimulatorSessionStore.load(fileURL: url))
    }
}

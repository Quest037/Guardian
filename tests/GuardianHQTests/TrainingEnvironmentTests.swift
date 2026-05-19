import XCTest
@testable import GuardianHQ

final class TrainingEnvironmentTests: XCTestCase {
    func test_manifest_roundTrip() throws {
        let manifest = TrainingEnvironmentManifest(
            id: "test-lot",
            displayName: "Test lot",
            description: "Unit test package",
            tags: ["ugv"],
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 5, yM: 1, zM: 0, yawDeg: 90)
        )
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(TrainingEnvironmentManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
    }

    func test_validator_rejectsUnsupportedFormatVersion() {
        let manifest = TrainingEnvironmentManifest(
            formatVersion: 99,
            id: "bad",
            displayName: "Bad",
            defaultSpawn: TrainingEnvironmentPose(xM: 0, yM: 0, zM: 0, yawDeg: 0),
            defaultGoal: TrainingEnvironmentPose(xM: 1, yM: 0, zM: 0, yawDeg: 0)
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-env-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertThrowsError(try TrainingEnvironmentValidator.validate(manifest: manifest, packageRoot: root)) { error in
            XCTAssertEqual(
                error as? TrainingEnvironmentValidationError,
                .unsupportedFormatVersion(99)
            )
        }
    }

    func test_catalogue_loadsBundledOpenField() {
        let packages = TrainingEnvironmentCatalogue.loadAll()
        XCTAssertTrue(
            packages.contains { $0.id == TrainingEnvironmentManifest.defaultBundledID },
            "Expected bundled guardian-open-field in catalogue"
        )
    }

    func test_selectionStore_roundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-env-sel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sel.json")

        try TrainingEnvironmentSelectionStore.setSelectedEnvironmentID(
            "guardian-open-field",
            task: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            fileURL: file
        )
        let id = try TrainingEnvironmentSelectionStore.selectedEnvironmentID(
            task: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            fileURL: file
        )
        XCTAssertEqual(id, "guardian-open-field")
    }

    func test_gazeboSessionLaunchPolicy() {
        XCTAssertFalse(GazeboSessionLaunchPolicy.requiresSimulateEnabled(for: .build))
        XCTAssertFalse(GazeboSessionLaunchPolicy.requiresSimulateEnabled(for: .preview))
        XCTAssertTrue(GazeboSessionLaunchPolicy.requiresSimulateEnabled(for: .run))
        XCTAssertFalse(GazeboSessionLaunchPolicy.headless(for: .preview))
    }

    func test_deleteUserPackage_rejectsBundled() {
        XCTAssertThrowsError(
            try TrainingEnvironmentCatalogue.deleteUserPackage(
                environmentID: TrainingEnvironmentManifest.defaultBundledID
            )
        ) { error in
            XCTAssertEqual(error as? TrainingEnvironmentCatalogueError, .cannotDeleteBundled)
        }
    }

    func test_deleteUserPackage_rejectsUnknownID() {
        XCTAssertThrowsError(
            try TrainingEnvironmentCatalogue.deleteUserPackage(environmentID: "no-such-world-\(UUID().uuidString)")
        ) { error in
            XCTAssertEqual(error as? TrainingEnvironmentCatalogueError, .packageNotFound)
        }
    }

    func test_selectionStore_removeReferences() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-env-sel-rm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("sel.json")

        try TrainingEnvironmentSelectionStore.setSelectedEnvironmentID(
            "user-world-a",
            task: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            fileURL: file
        )
        try TrainingEnvironmentSelectionStore.setSelectedEnvironmentID(
            "user-world-b",
            task: .approachSlotForward,
            fileURL: file
        )
        try TrainingEnvironmentSelectionStore.removeReferences(to: "user-world-a", fileURL: file)

        XCTAssertEqual(
            try TrainingEnvironmentSelectionStore.selectedEnvironmentID(
                task: .reverseIntoSlot,
                vehicleClass: .ugvWheeled,
                fileURL: file
            ),
            nil
        )
        XCTAssertEqual(
            try TrainingEnvironmentSelectionStore.selectedEnvironmentID(task: .approachSlotForward, fileURL: file),
            "user-world-b"
        )
    }

    func test_targetSlotStore_remove() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("guardian-env-slot-rm-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pose = TrainingTaskPose(
            latitudeDeg: 1,
            longitudeDeg: 2,
            headingDeg: 0,
            absoluteAltitudeM: 0
        )
        try TrainingTargetSlotStore.save(pose, environmentID: "env-a", fileURL: dir)
        try TrainingTargetSlotStore.save(pose, environmentID: "env-b", fileURL: dir)
        try TrainingTargetSlotStore.remove(environmentID: "env-a", fileURL: dir)
        XCTAssertNil(try TrainingTargetSlotStore.load(environmentID: "env-a", fileURL: dir))
        XCTAssertEqual(try TrainingTargetSlotStore.load(environmentID: "env-b", fileURL: dir), pose)
    }
}

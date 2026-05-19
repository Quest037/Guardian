import XCTest
@testable import GuardianHQ

final class GuardianBrainPinDefaultsStoreTests: XCTestCase {
    func test_pinAndSeedRunBindings() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianBrainPinTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let pinsURL = dir.appendingPathComponent("pins.json")
        let manifest = GuardianBrainPackManifest(
            formatVersion: 1,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(2),
            displayName: "Parking UGV",
            createdAt: Date(),
            trainingAppBuild: "0.0.39",
            vehicleClasses: [TrainingVehicleClass.ugvWheeled.rawValue],
            taskKinds: [TrainingTaskKind.reverseIntoSlot.rawValue],
            gazeboEnvironmentId: nil
        )
        try GuardianBrainPinDefaultsStore.pin(manifest: manifest, fileURL: pinsURL)
        let bindings = try GuardianBrainPinDefaultsStore.missionRunBindings(fileURL: pinsURL)
        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].brainVersion, 2)
        XCTAssertEqual(bindings[0].taskKindRaw, TrainingTaskKind.reverseIntoSlot.rawValue)
    }

    func test_missionProduct_includesBrainsSection() {
        XCTAssertTrue(GuardianAppProduct.mission.includesSidebarSection(.brains))
        XCTAssertFalse(GuardianAppProduct.training.includesSidebarSection(.brains))
    }
}

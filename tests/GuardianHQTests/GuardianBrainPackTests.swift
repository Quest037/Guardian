import XCTest
@testable import GuardianCore

final class GuardianBrainPackTests: XCTestCase {
    private func sampleSkill() -> TrainedVehicleSkill {
        TrainedVehicleSkill(
            taskKind: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            segments: [.forward(0.5, durationS: 2), .hold(durationS: 1)],
            score: TrainingSkillScore(
                positionErrorM: 0.4,
                headingErrorDeg: 3,
                episodeDurationS: 12,
                constraintViolations: [],
                succeeded: true
            ),
            layout: TrainingTaskLayoutFactory.layout(
                kind: .reverseIntoSlot,
                spawn: .default
            ),
            trialIndex: 3,
            summary: "fwd + hold"
        )
    }

    func test_roundTrip_encodeDecode() throws {
        let pack = try GuardianBrainPackBuilder.makePack(
            from: sampleSkill(),
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Test brain"
        )
        let data = try GuardianBrainPackCodec.sealedData(for: pack)
        let decoded = try GuardianBrainPackCodec.decode(data)
        XCTAssertEqual(decoded, pack)
    }

    func test_rejectsUnsupportedFormatVersion() throws {
        var pack = try GuardianBrainPackBuilder.makePack(
            from: sampleSkill(),
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Test"
        )
        pack.manifest.formatVersion = 99
        let data = try GuardianBrainPackCodec.sealedData(for: pack)
        XCTAssertThrowsError(try GuardianBrainPackCodec.decode(data)) { error in
            guard case GuardianBrainPackError.unsupportedFormatVersion(99) = error else {
                XCTFail("Expected unsupportedFormatVersion, got \(error)")
                return
            }
        }
    }

    func test_duplicateWrite_samePath_overwrites() throws {
        let pack = try GuardianBrainPackBuilder.makePack(
            from: sampleSkill(),
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(2),
            displayName: "Import test"
        )
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianBrainPackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let destURL = dir.appendingPathComponent(GuardianBrainPackFormat.packFileName)
        try GuardianBrainPackCodec.sealedData(for: pack).write(to: destURL)
        let firstSize = try Data(contentsOf: destURL).count

        var revised = pack
        revised.manifest.displayName = "Import test revised"
        try GuardianBrainPackCodec.sealedData(for: revised).write(to: destURL, options: .atomic)
        let secondSize = try Data(contentsOf: destURL).count

        XCTAssertNotEqual(firstSize, secondSize)
        let reloaded = try GuardianBrainPackCodec.decode(Data(contentsOf: destURL))
        XCTAssertEqual(reloaded.manifest.displayName, "Import test revised")
    }

    func test_catalogueImport_listsEntry() throws {
        let exportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianBrainPackExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportDir) }

        let pack = try GuardianBrainPackBuilder.makePack(
            from: sampleSkill(),
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Catalogue row"
        )
        let exportURL = exportDir.appendingPathComponent("brain.guardianbrain")
        try GuardianBrainPackExportService.write(pack: pack, to: exportURL)

        let entry = try GuardianBrainCatalogueStore.importPackFile(from: exportURL)
        XCTAssertEqual(entry.manifest.brainId, pack.manifest.brainId)
        XCTAssertEqual(entry.manifest.brainVersion, .initial)

        let again = try GuardianBrainCatalogueStore.importPackFile(from: exportURL)
        XCTAssertEqual(again.manifest.brainId, pack.manifest.brainId)
        XCTAssertEqual(again.manifest.brainVersion, .initial)

        let listed = try GuardianBrainCatalogueStore.listEntries()
        XCTAssertTrue(listed.contains(where: { $0.id == entry.id }))

        try GuardianBrainCatalogueStore.deleteEntry(entry)
    }
}

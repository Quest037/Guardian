import XCTest

@testable import GuardianCore

final class GuardianBrainDispatchResolverTests: XCTestCase {
    private var tempDir: URL!
    private var importedEntries: [GuardianBrainCatalogueEntry] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianBrainDispatchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for entry in importedEntries {
            try? GuardianBrainCatalogueStore.deleteEntry(entry)
        }
        importedEntries = []
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_resolve_segmentPath_when_pack_has_segments() throws {
        let skill = makeSkill()
        let pack = try GuardianBrainPackBuilder.makePack(
            from: skill,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Parking UGV"
        )
        _ = try importPack(pack)
        let binding = MissionRunBrainBinding(manifest: pack.manifest)
        let result = GuardianBrainDispatchResolver.resolve(
            fleetVehicleType: .ugvWheeled,
            bindings: [binding],
            fileManager: FileManager.default
        )
        guard case .success(let strategy) = result else {
            return XCTFail("Expected segment path, got \(result)")
        }
        guard case .segmentPath(let resolved, let formatVersion) = strategy else {
            return XCTFail("Expected segmentPath strategy")
        }
        XCTAssertEqual(resolved.brainId, binding.brainId)
        XCTAssertEqual(formatVersion, GuardianBrainPackFormat.currentFormatVersion)
    }

    func test_resolve_plannerPath_when_no_segments_but_planner_hints() throws {
        var pack = try GuardianBrainPackBuilder.makePack(
            from: makeSkill(segmentCount: 0),
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(2),
            displayName: "Nav hints"
        )
        pack.skill.segments = []
        pack.plannerHints = GuardianBrainPackPlannerHints(frameId: "map", maxSpeedMS: 1.0)
        _ = try importPack(pack)
        let binding = MissionRunBrainBinding(manifest: pack.manifest)
        let result = GuardianBrainDispatchResolver.resolve(
            fleetVehicleType: .ugvTracked,
            bindings: [binding],
            fileManager: FileManager.default
        )
        guard case .success(.plannerPath(let resolved, _)) = result else {
            return XCTFail("Expected planner path")
        }
        XCTAssertEqual(resolved.brainVersion, GuardianBrainVersion.fromLegacyInteger(2))
    }

    func test_resolve_noBinding_for_unmapped_fleet_type() {
        let binding = MissionRunBrainBinding(
            taskKindRaw: TrainingTaskKind.reverseIntoSlot.rawValue,
            vehicleClassRaw: TrainingVehicleClass.ugvWheeled.rawValue,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1),
            displayName: "Test"
        )
        let result = GuardianBrainDispatchResolver.resolve(
            fleetVehicleType: .usv,
            bindings: [binding]
        )
        XCTAssertEqual(result, .failure(.noBinding))
    }

    func test_correlationSource_is_stable() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let binding = MissionRunBrainBinding(
            taskKindRaw: "reverseIntoSlot",
            vehicleClassRaw: "ugvWheeled",
            brainId: id,
            brainVersion: GuardianBrainVersion.fromLegacyInteger(3),
            displayName: "X"
        )
        XCTAssertEqual(
            GuardianBrainDispatchResolver.correlationSource(for: binding),
            "brain:00000000-0000-0000-0000-000000000001:v0.0.3"
        )
    }

    private func makeSkill(segmentCount: Int = 1) -> TrainedVehicleSkill {
        let segments: [TrainingControlSegment] = segmentCount > 0
            ? [.forward(0.5, durationS: 2)]
            : []
        return TrainedVehicleSkill(
            taskKind: .reverseIntoSlot,
            vehicleClass: segmentCount > 0 ? .ugvWheeled : .ugvTracked,
            segments: segments,
            score: TrainingSkillScore(
                positionErrorM: 0.2,
                headingErrorDeg: 2,
                episodeDurationS: 8,
                constraintViolations: [],
                succeeded: true
            ),
            layout: TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default),
            trialIndex: 0,
            summary: "fixture"
        )
    }

    @discardableResult
    private func importPack(_ pack: GuardianBrainPack) throws -> GuardianBrainCatalogueEntry {
        let exportURL = tempDir.appendingPathComponent("\(UUID().uuidString).guardianbrain")
        try GuardianBrainPackExportService.write(pack: pack, to: exportURL)
        let entry = try GuardianBrainCatalogueStore.importPackFile(from: exportURL)
        importedEntries.append(entry)
        return entry
    }
}

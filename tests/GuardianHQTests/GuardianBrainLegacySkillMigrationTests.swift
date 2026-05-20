import XCTest

@testable import GuardianCore

@MainActor
final class GuardianBrainLegacySkillMigrationTests: XCTestCase {
    private var tempDir: URL!
    private var skillsURL: URL!
    private var brainsRoot: URL!
    private var flagKey: String!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianBrainLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        skillsURL = tempDir.appendingPathComponent("trained_vehicle_skills.json")
        brainsRoot = tempDir.appendingPathComponent("brains", isDirectory: true)
        flagKey = "GuardianBrainLegacySkillMigration.completed.\(UUID().uuidString)"
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: flagKey)
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_migrateIfNeeded_imports_legacy_skill_once() throws {
        let brainId = UUID()
        let skill = TrainedVehicleSkill(
            id: brainId,
            taskKind: .reverseIntoSlot,
            vehicleClass: .ugvWheeled,
            segments: [.forward(0.5, durationS: 1)],
            score: TrainingSkillScore(
                positionErrorM: 0.3,
                headingErrorDeg: 2,
                episodeDurationS: 5,
                constraintViolations: [],
                succeeded: true
            ),
            layout: TrainingTaskLayoutFactory.layout(kind: .reverseIntoSlot, spawn: .default),
            trialIndex: 0,
            summary: "legacy"
        )
        try TrainingSkillStore.appendPromoted(skill, fileURL: skillsURL)

        let first = GuardianBrainLegacySkillMigration.migrateIfNeeded(
            trainingSkillsFileURL: skillsURL,
            brainsRootOverride: brainsRoot,
            migrationCompletedUserDefaultsKey: flagKey
        )
        XCTAssertEqual(first?.importedCount, 1)
        let packURL = brainsRoot
            .appendingPathComponent(brainId.uuidString, isDirectory: true)
            .appendingPathComponent("1", isDirectory: true)
            .appendingPathComponent(GuardianBrainPackFormat.packFileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packURL.path))

        let second = GuardianBrainLegacySkillMigration.migrateIfNeeded(
            trainingSkillsFileURL: skillsURL,
            brainsRootOverride: brainsRoot,
            migrationCompletedUserDefaultsKey: flagKey
        )
        XCTAssertNil(second)
    }
}

import Foundation

/// One-time import of legacy `TrainingSkillStore` JSON into the brain catalogue (Mission app).
@MainActor
enum GuardianBrainLegacySkillMigration {
    private static let completedKey = "GuardianBrainLegacySkillMigration.completed"

    struct Result: Equatable, Sendable {
        var importedCount: Int
        var skippedExistingCount: Int
    }

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    @discardableResult
    static func migrateIfNeeded(
        trainingSkillsFileURL: URL? = nil,
        brainsRootOverride: URL? = nil,
        migrationCompletedUserDefaultsKey: String? = nil,
        fileManager: FileManager = .default
    ) -> Result? {
        let flagKey = migrationCompletedUserDefaultsKey ?? completedKey
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return nil }
        var imported = 0
        var skipped = 0
        do {
            let skills = try TrainingSkillStore.loadAll(fileURL: trainingSkillsFileURL)
            let brainsRoot: URL
            if let brainsRootOverride {
                brainsRoot = brainsRootOverride
            } else {
                brainsRoot = try GuardianBrainCatalogueStore.brainsRootURL(fileManager: fileManager)
            }
            try fileManager.createDirectory(at: brainsRoot, withIntermediateDirectories: true)
            for skill in skills {
                let brainId = skill.id
                let versionDir = brainsRoot
                    .appendingPathComponent(brainId.uuidString, isDirectory: true)
                    .appendingPathComponent(GuardianBrainVersion.initial.catalogueDirectoryName, isDirectory: true)
                let packURL = versionDir.appendingPathComponent(GuardianBrainPackFormat.packFileName)
                if fileManager.fileExists(atPath: packURL.path) {
                    skipped += 1
                    continue
                }
                let pack = try GuardianBrainPackBuilder.makePack(
                    from: skill,
                    brainId: brainId,
                    brainVersion: .initial,
                    displayName: GuardianBrainPackBuilder.defaultDisplayName(for: skill)
                )
                try fileManager.createDirectory(at: versionDir, withIntermediateDirectories: true)
                try GuardianBrainPackCodec.sealedData(for: pack).write(to: packURL, options: .atomic)
                imported += 1
            }
            UserDefaults.standard.set(true, forKey: flagKey)
            return Result(importedCount: imported, skippedExistingCount: skipped)
        } catch {
            return nil
        }
    }
}

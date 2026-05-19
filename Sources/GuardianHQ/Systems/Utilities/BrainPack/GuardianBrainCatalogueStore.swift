import Foundation

/// Imported brain packs for the Mission app (`Application Support/Guardian/brains/...`).
enum GuardianBrainCatalogueStore {
    static func brainsRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw GuardianBrainPackError.importFailed("Application Support is unavailable.")
        }
        let root = base.appendingPathComponent("Guardian/brains", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func packDirectoryURL(
        brainId: UUID,
        brainVersion: GuardianBrainVersion,
        fileManager: FileManager = .default
    ) throws -> URL {
        try brainsRootURL(fileManager: fileManager)
            .appendingPathComponent(brainId.uuidString, isDirectory: true)
            .appendingPathComponent(brainVersion.catalogueDirectoryName, isDirectory: true)
    }

    static func packFileURL(
        brainId: UUID,
        brainVersion: GuardianBrainVersion,
        fileManager: FileManager = .default
    ) throws -> URL {
        try packDirectoryURL(brainId: brainId, brainVersion: brainVersion, fileManager: fileManager)
            .appendingPathComponent(GuardianBrainPackFormat.packFileName)
    }

    static func listEntries(fileManager: FileManager = .default) throws -> [GuardianBrainCatalogueEntry] {
        let root = try brainsRootURL(fileManager: fileManager)
        guard let brainDirs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var entries: [GuardianBrainCatalogueEntry] = []
        for brainDir in brainDirs where (try? brainDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            guard let versionDirs = try? fileManager.contentsOfDirectory(
                at: brainDir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for versionDir in versionDirs where (try? versionDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let packURL = versionDir.appendingPathComponent(GuardianBrainPackFormat.packFileName)
                guard fileManager.fileExists(atPath: packURL.path),
                      let data = try? Data(contentsOf: packURL),
                      let pack = try? GuardianBrainPackCodec.decode(data) else { continue }
                let importedAt = (try? versionDir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                entries.append(
                    GuardianBrainCatalogueEntry(
                        manifest: pack.manifest,
                        packFileURL: packURL,
                        importedAt: importedAt
                    )
                )
            }
        }
        return entries.sorted {
            if $0.manifest.brainId != $1.manifest.brainId {
                return $0.manifest.displayName.localizedCaseInsensitiveCompare($1.manifest.displayName) == .orderedAscending
            }
            return $0.manifest.brainVersion > $1.manifest.brainVersion
        }
    }

    static func maxBrainVersion(brainId: UUID, fileManager: FileManager = .default) throws -> GuardianBrainVersion? {
        let versions = try listEntries(fileManager: fileManager)
            .filter { $0.manifest.brainId == brainId }
            .map(\.manifest.brainVersion)
        return versions.max()
    }

    /// Next patch after the highest catalogue + optional in-session export peak (e.g. `0.3.45` → `0.3.46`).
    static func nextPatchVersion(
        brainId: UUID,
        sessionPeak: GuardianBrainVersion?,
        fileManager: FileManager = .default
    ) throws -> GuardianBrainVersion {
        let catalogueMax = try maxBrainVersion(brainId: brainId, fileManager: fileManager)
        let candidates = [catalogueMax, sessionPeak].compactMap { $0 }
        guard let peak = candidates.max() else { return .initial }
        return peak.bumped(.patch)
    }

    @discardableResult
    static func importPackFile(
        from sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> GuardianBrainCatalogueEntry {
        let data = try Data(contentsOf: sourceURL)
        let pack = try GuardianBrainPackCodec.decode(data)
        let destination = try packFileURL(
            brainId: pack.manifest.brainId,
            brainVersion: pack.manifest.brainVersion,
            fileManager: fileManager
        )
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try data.write(to: destination, options: .atomic)
        return GuardianBrainCatalogueEntry(
            manifest: pack.manifest,
            packFileURL: destination,
            importedAt: Date()
        )
    }

    static func deleteEntry(_ entry: GuardianBrainCatalogueEntry, fileManager: FileManager = .default) throws {
        let directory = entry.packFileURL.deletingLastPathComponent()
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        let brainDir = directory.deletingLastPathComponent()
        if let children = try? fileManager.contentsOfDirectory(atPath: brainDir.path), children.isEmpty {
            try? fileManager.removeItem(at: brainDir)
        }
    }
}

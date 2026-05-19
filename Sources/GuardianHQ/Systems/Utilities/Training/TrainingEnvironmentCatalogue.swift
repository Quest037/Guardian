import Foundation

/// Merges bundled and user training environment packages.
enum TrainingEnvironmentCatalogue {
    static func loadAll() -> [TrainingEnvironmentPackage] {
        var packages: [TrainingEnvironmentPackage] = []
        var seenIDs: Set<String> = []

        if let bundledRoot = TrainingEnvironmentStore.bundledEnvironmentsRootURL() {
            for dir in TrainingEnvironmentStore.packageDirectories(under: bundledRoot) {
                if let pkg = loadPackage(at: dir, source: .bundled), !seenIDs.contains(pkg.id) {
                    packages.append(pkg)
                    seenIDs.insert(pkg.id)
                }
            }
        }

        if let userRoot = try? TrainingEnvironmentStore.userEnvironmentsRootURL() {
            for dir in TrainingEnvironmentStore.packageDirectories(under: userRoot) {
                if let pkg = loadPackage(at: dir, source: .user), !seenIDs.contains(pkg.id) {
                    packages.append(pkg)
                    seenIDs.insert(pkg.id)
                }
            }
        }

        return packages.sorted { $0.manifest.displayName.localizedCaseInsensitiveCompare($1.manifest.displayName) == .orderedAscending }
    }

    static func package(id: String) -> TrainingEnvironmentPackage? {
        loadAll().first { $0.id == id }
    }

    static func loadPackage(at packageRoot: URL, source: TrainingEnvironmentSource) -> TrainingEnvironmentPackage? {
        do {
            let manifest = try TrainingEnvironmentStore.loadManifest(from: packageRoot)
            try TrainingEnvironmentValidator.validate(manifest: manifest, packageRoot: packageRoot)
            return TrainingEnvironmentPackage(manifest: manifest, packageRootURL: packageRoot, source: source)
        } catch {
            return nil
        }
    }

    /// Writes a validated user package (create or replace).
    static func saveUserPackage(
        manifest: TrainingEnvironmentManifest,
        worldFileSourceURL: URL
    ) throws -> TrainingEnvironmentPackage {
        let root = try TrainingEnvironmentStore.userPackageRoot(environmentID: manifest.id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destWorld = root.appendingPathComponent(manifest.worldFile, isDirectory: false)
        if worldFileSourceURL.standardizedFileURL != destWorld.standardizedFileURL {
            if FileManager.default.fileExists(atPath: destWorld.path) {
                try FileManager.default.removeItem(at: destWorld)
            }
            try FileManager.default.copyItem(at: worldFileSourceURL, to: destWorld)
        }
        try TrainingEnvironmentStore.saveManifest(manifest, packageRoot: root)
        try TrainingEnvironmentValidator.validate(manifest: manifest, packageRoot: root)
        return TrainingEnvironmentPackage(manifest: manifest, packageRootURL: root, source: .user)
    }

    /// Import a folder that already contains `manifest.json` + world file.
    static func importPackage(from sourceDirectory: URL) throws -> TrainingEnvironmentPackage {
        let manifest = try TrainingEnvironmentStore.loadManifest(from: sourceDirectory)
        let root = try TrainingEnvironmentStore.userPackageRoot(environmentID: manifest.id)
        let fm = FileManager.default
        if fm.fileExists(atPath: root.path) {
            try fm.removeItem(at: root)
        }
        try fm.copyItem(at: sourceDirectory, to: root)
        try TrainingEnvironmentValidator.validate(manifest: manifest, packageRoot: root)
        return TrainingEnvironmentPackage(manifest: manifest, packageRootURL: root, source: .imported)
    }

    /// Export package directory to a new folder URL (caller provides destination parent).
    static func exportPackage(_ package: TrainingEnvironmentPackage, to destinationRoot: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationRoot.path) {
            try fm.removeItem(at: destinationRoot)
        }
        try fm.copyItem(at: package.packageRootURL, to: destinationRoot)
    }
}

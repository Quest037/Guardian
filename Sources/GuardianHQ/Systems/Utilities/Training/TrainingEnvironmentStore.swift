import Foundation

/// Paths and I/O for training environment packages (bundled + Application Support).
enum TrainingEnvironmentStore {
    static let manifestFileName = "manifest.json"
    static let userEnvironmentsFolderName = "environments"
    static let builderDraftsFolderName = "builder-drafts"

    static func userEnvironmentsRootURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            throw NSError(domain: "TrainingEnvironmentStore", code: 1)
        }
        let dir = base
            .appendingPathComponent("Guardian/training", isDirectory: true)
            .appendingPathComponent(userEnvironmentsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func bundledEnvironmentsRootURL() -> URL? {
        GuardianBundledResourceLocator.subdirectoryURL(
            "TrainingEnvironments",
            in: GuardianBundledResourceLocator.trainingSimulationResourceBundles
        )
    }

    static func packageDirectories(under root: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    static func loadManifest(from packageRoot: URL) throws -> TrainingEnvironmentManifest {
        let url = packageRoot.appendingPathComponent(manifestFileName, isDirectory: false)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(TrainingEnvironmentManifest.self, from: data)
    }

    static func saveManifest(_ manifest: TrainingEnvironmentManifest, packageRoot: URL) throws {
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let url = packageRoot.appendingPathComponent(manifestFileName, isDirectory: false)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    static func userPackageRoot(environmentID: String) throws -> URL {
        try userEnvironmentsRootURL().appendingPathComponent(environmentID, isDirectory: true)
    }

    /// Staging folder for unsaved World Builder drafts (`manifest.json` + `world.sdf`).
    static func builderDraftPackageRoot(folderName: String) throws -> URL {
        let trainingRoot = try userEnvironmentsRootURL().deletingLastPathComponent()
        let draftsRoot = trainingRoot.appendingPathComponent(builderDraftsFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: draftsRoot, withIntermediateDirectories: true)
        let root = draftsRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

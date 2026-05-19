import Foundation

/// Paths and I/O for training environment packages (bundled + Application Support).
enum TrainingEnvironmentStore {
    static let manifestFileName = "manifest.json"
    static let userEnvironmentsFolderName = "environments"

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
        guard let res = Bundle.module.resourceURL else { return nil }
        let root = res.appendingPathComponent("TrainingEnvironments", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return root
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
}

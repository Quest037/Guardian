import Foundation

/// Resolves SwiftPM resource bundles for Guardian executables (core vs Training simulation assets).
enum GuardianBundledResourceLocator {
    /// SPM resource bundle names for Training-only assets (Gazebo runtime, gzweb viewer, environment packages).
    static let trainingSimulationBundleBaseNames = [
        "GuardianTrainingSimulationResources_GuardianTrainingSimulationResources",
        // Xcode SwiftPM integration (package name + target name).
        "GuardianHQ_GuardianTrainingSimulationResources",
        "GuardianTraining_GuardianTrainingSimulationResources",
        // Cutover: monolith / pre-split bundles that still embed training assets in the core module bundle.
        "GuardianCore_GuardianCore",
        "GuardianHQ_GuardianHQ",
        "GuardianHQ_GuardianCore",
    ]

    /// Bundles to search for shared Guardian assets (logos, SITL, fleet bodies, …).
    static var coreResourceBundles: [Bundle] {
        discoveredBundles(named: [
            "GuardianCore_GuardianCore",
            "GuardianHQ_GuardianHQ",
        ]) + [Bundle.module, Bundle.main]
    }

    /// Bundles that may contain Gazebo / training environment resources (absent in Mission-only links).
    static var trainingSimulationResourceBundles: [Bundle] {
        var bundles = discoveredBundles(named: trainingSimulationBundleBaseNames)
        if !bundles.contains(where: { $0.bundleURL == Bundle.module.bundleURL }) {
            bundles.append(Bundle.module)
        }
        return bundles
    }

    static func subdirectoryURL(_ subdirectory: String, in bundles: [Bundle]) -> URL? {
        for bundle in bundles {
            guard let root = bundle.resourceURL else { continue }
            let url = root.appendingPathComponent(subdirectory, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }

    static func url(
        forResource name: String,
        withExtension ext: String?,
        subdirectory: String? = nil,
        in bundles: [Bundle]
    ) -> URL? {
        for bundle in bundles {
            if let subdirectory,
               let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    /// Offline gzweb viewer page (`guardian_viewer.html` + sibling `dist/gzweb.bundle.mjs`).
    static func gazeboWebViewerHTMLURL(in bundles: [Bundle] = trainingSimulationResourceBundles) -> URL? {
        url(forResource: "guardian_viewer", withExtension: "html", subdirectory: "GazeboWeb", in: bundles)
            ?? url(forResource: "guardian_viewer", withExtension: "html", in: bundles)
    }

    private static func discoveredBundles(named baseNames: [String]) -> [Bundle] {
        var seen = Set<String>()
        var result: [Bundle] = []
        for base in baseNames {
            for bundle in candidateParentBundles() {
                guard let url = bundle.url(forResource: base, withExtension: "bundle"),
                      let nested = Bundle(url: url) else { continue }
                let key = nested.bundleURL.path
                guard seen.insert(key).inserted else { continue }
                result.append(nested)
            }
        }
        return result
    }

    private static func candidateParentBundles() -> [Bundle] {
        var parents: [Bundle] = [Bundle.main, Bundle.module]
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            if let execBundle = Bundle(url: execDir) {
                parents.append(execBundle)
            }
            let moduleName = Bundle.module.bundleURL.lastPathComponent
            if moduleName.hasSuffix(".bundle") {
                let nested = execDir.appendingPathComponent(moduleName, isDirectory: true)
                if FileManager.default.fileExists(atPath: nested.path),
                   let nestedBundle = Bundle(url: nested) {
                    parents.append(nestedBundle)
                }
            }
        }
        if let resourceURL = Bundle.main.resourceURL,
           let resourceBundle = Bundle(url: resourceURL) {
            parents.append(resourceBundle)
        }
        return parents
    }
}

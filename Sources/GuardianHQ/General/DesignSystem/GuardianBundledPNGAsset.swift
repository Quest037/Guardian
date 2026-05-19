import AppKit

/// Resolves PNG files copied into the ``GuardianHQ`` SwiftPM resource bundle.
enum GuardianBundledPNGAsset {
    static func nsImage(resourceName: String) -> NSImage? {
        guard let url = resolveURL(resourceName: resourceName) else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }

    static func resolveURL(resourceName: String) -> URL? {
        let relative = "\(resourceName).png"
        var bundles: [Bundle] = [Bundle.module, Bundle.main]

        let moduleName = Bundle.module.bundleURL.lastPathComponent
        if moduleName.hasSuffix(".bundle"),
           let nested = Bundle.main.resourceURL?.appendingPathComponent(moduleName, isDirectory: true),
           FileManager.default.fileExists(atPath: nested.path),
           let nestedBundle = Bundle(url: nested) {
            bundles.append(nestedBundle)
        }

        for bundle in bundles {
            let atBundleRoot = bundle.bundleURL.appendingPathComponent(relative)
            if FileManager.default.isReadableFile(atPath: atBundleRoot.path) {
                return atBundleRoot
            }
            if let resourceURL = bundle.resourceURL {
                let candidate = resourceURL.appendingPathComponent(relative)
                if FileManager.default.isReadableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            if let url = bundle.url(forResource: resourceName, withExtension: "png"),
               FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

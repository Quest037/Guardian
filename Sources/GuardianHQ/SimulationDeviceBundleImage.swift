import AppKit
import Foundation
import SwiftUI

/// SwiftPM copies resources at the **root** of `…_GuardianHQ.bundle` (e.g. `SimulationDevices/…`),
/// not under `Contents/Resources`, so `Bundle.url(forResource:subdirectory:)` often fails. Resolve paths explicitly.
enum SimulationDeviceBundleImage {
    /// First basename in `names` that resolves to a readable PNG.
    static func pngURL(firstMatching names: [String]) -> URL? {
        for name in names {
            if let url = pngURL(named: name) {
                return url
            }
        }
        return nil
    }

    static func pngURL(named name: String) -> URL? {
        let relative = "SimulationDevices/\(name).png"
        var bundles: [Bundle] = [Bundle.module, Bundle.main]

        // Some app bundles nest the SPM resource bundle under Resources (name matches `…_….bundle`).
        let moduleName = Bundle.module.bundleURL.lastPathComponent
        if moduleName.hasSuffix(".bundle"),
           let nested = Bundle.main.resourceURL?.appendingPathComponent(moduleName, isDirectory: true),
           FileManager.default.fileExists(atPath: nested.path),
           let nestedBundle = Bundle(url: nested) {
            bundles.append(nestedBundle)
        }

        for b in bundles {
            if let url = pngURL(relativeToBundle: b, relative: relative) {
                return url
            }
        }
        return nil
    }

    private static func pngURL(relativeToBundle b: Bundle, relative: String) -> URL? {
        let atBundleRoot = b.bundleURL.appendingPathComponent(relative)
        if FileManager.default.isReadableFile(atPath: atBundleRoot.path) {
            return atBundleRoot
        }

        let name = (relative as NSString).lastPathComponent.replacingOccurrences(of: ".png", with: "")
        if let u = b.url(forResource: name, withExtension: "png", subdirectory: "SimulationDevices"),
           FileManager.default.isReadableFile(atPath: u.path) {
            return u
        }

        if let res = b.resourceURL {
            let u = res.appendingPathComponent(relative)
            if FileManager.default.isReadableFile(atPath: u.path) {
                return u
            }
        }

        return nil
    }

    static func nsImage(named name: String) -> NSImage? {
        nsImage(firstMatching: [name])
    }

    static func nsImage(firstMatching names: [String]) -> NSImage? {
        guard let url = pngURL(firstMatching: names) else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        // PNGs must not be interpreted as templates (SwiftUI `Button` labels tint template images).
        image.isTemplate = false
        return image
    }
}

/// Bundled `SimulationDevices/<name>.png`, or a neutral placeholder.
struct SimulationDeviceThumbnail: View {
    let imageBasenames: [String]

    init(imageBasenames: [String]) {
        self.imageBasenames = imageBasenames
    }

    /// Single-name convenience (tries only that basename).
    init(imageName: String) {
        self.imageBasenames = [imageName]
    }

    var body: some View {
        Group {
            if let img = SimulationDeviceBundleImage.nsImage(firstMatching: imageBasenames) {
                Image(nsImage: img)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(red: 0.16, green: 0.16, blue: 0.17)
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.gray.opacity(0.6))
                }
            }
        }
    }
}

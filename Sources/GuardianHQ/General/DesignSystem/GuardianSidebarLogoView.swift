import AppKit
import SwiftUI

/// Bundled ``Resources/sidebar_logo.png`` for the main nav rail header (collapsed + expanded).
enum GuardianSidebarLogoAsset {
    static let nsImage: NSImage? = {
        guard let url = resolveSidebarLogoURL() else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }()

    private static func resolveSidebarLogoURL() -> URL? {
        let relative = "sidebar_logo.png"
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
            if let url = bundle.url(forResource: "sidebar_logo", withExtension: "png"),
               FileManager.default.isReadableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

struct GuardianSidebarLogoView: View {
    var maxHeight: CGFloat = 28

    var body: some View {
        Group {
            if let image = GuardianSidebarLogoAsset.nsImage {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxHeight: maxHeight)
            } else {
                Image(systemName: "photo")
                    .font(GuardianTypography.relativeFixed(size: max(12, maxHeight * 0.45), weight: .medium, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .frame(height: maxHeight)
            }
        }
        .accessibilityLabel("Guardian")
    }
}

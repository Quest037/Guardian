import AppKit
import SwiftUI

/// Bundled ``Resources/sidebar_logo.png`` — purple pointed **G** for the nav rail header.
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

/// Sidebar header brand: bundled purple **G**; optional theme-aware **uardian** when the rail is expanded.
struct GuardianSidebarLogoView: View {
    var maxHeight: CGFloat = 28
    /// When true, appends **uardian** beside the mark (full word reads as Guardian).
    var showsWordmark: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// ``sidebar_logo.png`` aspect (209 × 191).
    private var markWidth: CGFloat { maxHeight * (209 / 191) }

    private var wordmarkFontSize: CGFloat { max(16, maxHeight * 0.69) }

    var body: some View {
        HStack(alignment: .center, spacing: showsWordmark ? GuardianSpacing.xsTight : 0) {
            markView
                .frame(width: markWidth, height: maxHeight)

            if showsWordmark {
                Text("uardian")
                    .font(
                        GuardianTypography.relativeFixed(
                            size: wordmarkFontSize,
                            weight: .bold,
                            relativeTo: .title2
                        )
                    )
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guardian")
    }

    @ViewBuilder
    private var markView: some View {
        if let image = GuardianSidebarLogoAsset.nsImage {
            Image(nsImage: image)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: markWidth, height: maxHeight)
        } else {
            GuardianPointedGMark()
                .frame(width: markWidth, height: maxHeight)
        }
    }
}

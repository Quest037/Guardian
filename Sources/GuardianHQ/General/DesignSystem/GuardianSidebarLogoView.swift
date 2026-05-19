import AppKit
import SwiftUI

/// Bundled sidebar mark PNG for the active app product (`sidebar_logo` or `sidebar_logo_training`).
enum GuardianSidebarLogoAsset {
    static func nsImage(for product: GuardianAppProduct) -> NSImage? {
        GuardianBundledPNGAsset.nsImage(resourceName: product.sidebarLogoResourceName)
    }
}

/// Sidebar header brand: bundled purple **G**; optional theme-aware **uardian** when the rail is expanded.
struct GuardianSidebarLogoView: View {
    var maxHeight: CGFloat = 28
    /// When true, appends **uardian** beside the mark (full word reads as Guardian).
    var showsWordmark: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.guardianAppProduct) private var appProduct

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    /// ``sidebar_logo.png`` aspect (209 × 191).
    private var markWidth: CGFloat { maxHeight * (209 / 191) }

    private var wordmarkFontSize: CGFloat { max(16, maxHeight * 0.69) }

    private var accessibilityBrandLabel: String {
        appProduct.displayName
    }

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
        .accessibilityLabel(accessibilityBrandLabel)
    }

    @ViewBuilder
    private var markView: some View {
        if let image = GuardianSidebarLogoAsset.nsImage(for: appProduct) {
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

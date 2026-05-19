import SwiftUI

/// Settings → Missions shortcut to the full **Brains** catalogue.
struct GuardianBrainCatalogueSettingsSection: View {
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            Text("Use the **Brains** sidebar tab for import, pin defaults, and delete. Settings keeps this link for operators who start in Missions preferences.")
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

import SwiftUI

// MARK: - OperatorPromptAttributionCaption

/// Single-line “Source: …” for operator prompt surfaces (MC-R / Live Drive / Decisions / sticky toast).
struct OperatorPromptAttributionCaption: View {

    let source: OperatorPromptDisplaySource
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Text("Source: \(source.operatorFacingShortLabel)")
            .font(GuardianTypography.font(.denseCaption10Semibold))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Source: \(source.operatorFacingShortLabel)")
    }
}

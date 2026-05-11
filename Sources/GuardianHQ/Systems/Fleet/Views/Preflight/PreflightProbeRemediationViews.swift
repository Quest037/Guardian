import SwiftUI

/// Shared remediation copy for preflight probe failures (Mission Control preflight + Vehicles preflight check).
struct PreflightProbeRemediationBlock: View {
    let advice: PreflightFailureRemediationAdvice

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text(advice.summary)
                .font(GuardianTypography.font(.inlineNoticeTitle))
                .foregroundStyle(GuardianSemanticColors.warningStroke)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(advice.steps.enumerated()), id: \.offset) { _, step in
                Text("• \(step)")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, GuardianSpacing.micro)
    }
}

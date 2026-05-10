import SwiftUI

/// Shared remediation copy for preflight probe failures (Mission Control preflight + Vehicles preflight check).
struct PreflightProbeRemediationBlock: View {
    let advice: PreflightFailureRemediationAdvice

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(advice.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GuardianSemanticColors.warningStroke)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(advice.steps.enumerated()), id: \.offset) { _, step in
                Text("• \(step)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

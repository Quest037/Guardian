import SwiftUI

/// Shared remediation copy for arm probe failures (Mission Control preflight + Vehicles test arm).
struct ArmProbeRemediationBlock: View {
    let advice: ArmFailureRemediationAdvice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(advice.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(advice.steps.enumerated()), id: \.offset) { _, step in
                Text("• \(step)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.gray.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

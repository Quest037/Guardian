// MissionLiveTaskTriageOverlaySkeleton.swift — MC-R task triage: pulsing skeleton while heavy content defers to overlay animation end.
import SwiftUI

/// Placeholder body under the triage header; bar heights approximate state banner + copy + progress + wind-down stack.
struct MissionLiveTaskTriageOverlaySkeleton: View {
    private static let rows: [(height: CGFloat, widthFraction: CGFloat)] = [
        (height: 40, widthFraction: 1.0),
        (height: 14, widthFraction: 0.52),
        (height: 14, widthFraction: 0.68),
        (height: 132, widthFraction: 1.0),
        (height: 14, widthFraction: 0.44),
        (height: 48, widthFraction: 1.0),
    ]

    var body: some View {
        GuardianPulsingSkeletonBlockStack(rows: Self.rows)
            .padding(.horizontal, GuardianCardLayout.defaultBodyPadding)
            .padding(.top, GuardianSpacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

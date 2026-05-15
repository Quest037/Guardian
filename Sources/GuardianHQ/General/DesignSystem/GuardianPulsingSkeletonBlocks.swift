// GuardianPulsingSkeletonBlocks.swift — pulsing gray placeholder bars for loading / deferred UI (candidate for Theme §8.2 catalog).
import SwiftUI

/// Single horizontal skeleton segment with a soft sine pulse (no spinner).
struct GuardianPulsingSkeletonBar: View {
    let height: CGFloat
    var cornerRadius: CGFloat = 5
    /// When `nil`, expands to the parent width.
    var maxWidth: CGFloat? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = 0.5 + 0.5 * sin(t * 2 * .pi / 1.25)
            let base = colorScheme == .dark ? 0.36 : 0.40
            if let w = maxWidth {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.borderSubtle)
                    .opacity(base + 0.28 * phase)
                    .frame(width: w, height: height, alignment: .leading)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.borderSubtle)
                    .opacity(base + 0.28 * phase)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
    }
}

/// Stacked bars shaped like dense operator content (e.g. MC-R task triage body).
struct GuardianPulsingSkeletonBlockStack: View {
    let rows: [(height: CGFloat, widthFraction: CGFloat)]

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    let barW = max(44, w * CGFloat(min(1, max(0.08, row.widthFraction))))
                    GuardianPulsingSkeletonBar(
                        height: row.height,
                        maxWidth: barW
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }
}

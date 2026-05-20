import SwiftUI

/// Scrollable, selectable map-load log strip for embedded Gazebo viewports (Debug toggle only).
struct WorldBuilderMapDebugOverlay: View {
    let lines: [String]
    let theme: GuardianThemePalette
    var title: String = "Map log"
    var accessibilityLabel: String = "Map debug log"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)

            HStack(spacing: GuardianSpacing.xs) {
                Text(title)
                    .font(GuardianTypography.font(.denseCaption10Regular))
                    .foregroundStyle(theme.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GuardianSpacing.sm)
            .padding(.top, GuardianSpacing.xxs)

            ScrollView {
                Group {
                    if lines.isEmpty {
                        Text("No map log entries yet.")
                            .font(GuardianTypography.font(.denseCaption12Medium))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        Text(lines.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, GuardianSpacing.sm)
                .padding(.bottom, GuardianSpacing.sm)
            }
            .frame(maxHeight: 168)
        }
        .background(theme.backgroundRaised.opacity(0.94))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

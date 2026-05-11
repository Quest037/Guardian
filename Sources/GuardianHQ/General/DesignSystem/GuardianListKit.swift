import SwiftUI

// MARK: - List & table patterns (Theme §7)
//
// **Selection & keyboard (§7.2):** For native `List` / `Table` with a `selection` binding, prefer system row chrome (focus ring, arrow keys, VoiceOver) and `listRowBackground` for the selected fill. `GuardianSelectableListRow` targets custom stacks (cards, inspector columns) where you still want the same `backgroundActive` fill.
//
// **Ledger / log rows (§7.3):** `GuardianMonoLedgerRow` uses caption + monospace value. Zebra is a subtle alternating wash; separators default to a hairline above each row (`showTopSeparator: false` on the first row). System `List` / `Table` on macOS supplies hover; for bespoke stacks, add `.onHover` at the container if needed.

// MARK: - Settings row (§7.1)

/// Settings-style row: optional **leading SF Symbol**, **title**, optional **value**, **chevron**, full-width hit target (not ``NavigationLink``).
///
/// ``GuardianDisclosureSettingRow`` is a thin convenience wrapper with no icon.
struct GuardianSettingsRow: View {
    let title: String
    var systemImage: String? = nil
    var value: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: GuardianSpacing.denseGutter) {
                if let systemImage, !systemImage.isEmpty {
                    Image(systemName: systemImage)
                        .font(GuardianTypography.font(.disclosureRowTitle))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 22, alignment: .center)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(GuardianTypography.font(.disclosureRowTitle))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: GuardianSpacing.xs)
                if let value, !value.isEmpty {
                    Text(value)
                        .font(GuardianTypography.font(.disclosureRowValue))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(GuardianTypography.font(.disclosureChevron))
                    .foregroundStyle(theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
    }
}

// MARK: - Selectable row (custom stacks) — §7.2

/// Tappable row with **selected** styling for **non-`List`** stacks (inspector columns, card lists).
struct GuardianSelectableListRow<Label: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder private var label: () -> Label

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.isSelected = isSelected
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, GuardianSpacing.xs)
                .padding(.horizontal, GuardianSpacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? theme.backgroundActive : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
    }
}

// MARK: - Monospace ledger row — §7.3

/// Dense **caption · monospace value** row (telemetry, log tail, inspector facts).
struct GuardianMonoLedgerRow: View {
    let caption: String
    let value: String
    var zebra: Bool = false
    var showTopSeparator: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showTopSeparator {
                Divider()
                    .opacity(0.22)
            }
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
                Text(caption)
                    .font(GuardianTypography.font(.disclosureRowValue))
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: GuardianSpacing.xs)
                Text(value)
                    .font(GuardianTypography.font(.telemetryMono10Regular))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, GuardianSpacing.xxs)
            .padding(.horizontal, GuardianSpacing.xxs)
            .background(zebra ? zebraWash : Color.clear)
        }
    }

    private var zebraWash: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
    }
}

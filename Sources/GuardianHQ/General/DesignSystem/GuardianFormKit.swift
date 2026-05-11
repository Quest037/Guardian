import SwiftUI

// MARK: - Validation routing (Theme §6.2)

/// ## Where to show validation / status (operator UI)
///
/// | Surface | Use when | Avoid |
/// | --- | --- | --- |
/// | **Under field** (``GuardianLabeledFormField/error``) | Single-field mistakes (format, empty required, numeric range) the operator fixes in place. | Long policy copy or multi-field summaries. |
/// | **Inline notice** (``GuardianInlineNotice``) | Cross-field / policy blockers, warnings that need body copy + optional actions on the same screen. | Ephemeral acks. |
/// | **Toast** (``ToastCenter``) | Short-lived **acks** (“Saved”, “Copied”) or background work results — **not** primary form error UI. | Blocking validation the user must read before continuing. |
/// | **Confirm** (``guardianConfirmOverlay``) | Destructive submit, irreversible ops, or explicit branch decisions. | Inline field hints. |
///
/// **Primary actions:** disable the blue confirm when required fields are invalid *if* the form is modal-like; keep the reason visible via ``GuardianLabeledFormField/error`` or an inline notice at the top of the sheet.

// MARK: - Layout constants (Theme §6.3)

/// Heights and rhythm shared by form rows so ``TextField`` / ``Picker`` align with ``GuardianChromeSize/small`` tool rows (28pt control height).
enum GuardianFormLayout {
    /// Match ``GuardianChromeSize/small`` ``controlOuterHeight`` for a single-line field or segmented control.
    static let compactFieldOuterHeight: CGFloat = 28
}

extension View {
    /// Applies ``ControlSize/small`` and a **minimum height** so ``TextField`` / ``Picker`` / ``SecureField`` align with themed buttons on the same card.
    func guardianFormControlSizing() -> some View {
        controlSize(.small)
            .frame(minHeight: GuardianFormLayout.compactFieldOuterHeight, alignment: .center)
    }
}

// MARK: - Segmented picker row (Theme §6.4)

/// Stacked **label** + optional **subtitle** + ``Picker`` in **segmented** style — replaces ad-hoc `VStack + Picker` blocks in settings-style surfaces.
struct GuardianLabeledSegmentedPicker<Selection: Hashable>: View {
    let label: String
    var subtitle: String? = nil
    @Binding var selection: Selection
    let options: [(title: String, value: Selection)]
    var maxSegmentedWidth: CGFloat = 360

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(label)
                .font(GuardianTypography.font(.formFieldLabel))
                .foregroundStyle(theme.textSecondary)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("", selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                    Text(pair.title).tag(pair.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: maxSegmentedWidth, alignment: .leading)
            .guardianFormControlSizing()
        }
    }
}

import SwiftUI

/// Min/max altitude envelope and reference — one row per ``MissionGeofence`` (template or run augmentation).
struct MissionGeofenceAltitudeEnvelopeSection: View {
    @Binding var fence: MissionGeofence
    var formLabelColumn: CGFloat = 140

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var altitudeOrderWarning: Bool {
        fence.minAltitudeMeters >= fence.maxAltitudeMeters
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            GuardianLabeledFormField(
                label: "Min altitude",
                subtitle: "Lower bound of the allowed band (meters).",
                layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
            ) {
                TextField(
                    "0",
                    value: Binding(
                        get: { fence.minAltitudeMeters },
                        set: {
                            var g = fence
                            g.minAltitudeMeters = $0
                            fence = g
                        }
                    ),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
                .guardianFormControlSizing()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GuardianLabeledFormField(
                label: "Max altitude",
                subtitle: "Upper bound of the allowed band (meters).",
                layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
            ) {
                TextField(
                    "120",
                    value: Binding(
                        get: { fence.maxAltitudeMeters },
                        set: {
                            var g = fence
                            g.maxAltitudeMeters = $0
                            fence = g
                        }
                    ),
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)
                .guardianFormControlSizing()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GuardianLabeledFormField(label: "Altitude units", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                Picker(
                    "",
                    selection: Binding(
                        get: { fence.altitudeUnits },
                        set: {
                            var g = fence
                            g.altitudeUnits = $0
                            fence = g
                        }
                    )
                ) {
                    ForEach(MissionGeofenceAltitudeUnits.allCases) { u in
                        Text(u.displayTitle).tag(u)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GuardianLabeledFormField(
                label: "Altitude reference",
                subtitle: "How min/max altitudes are interpreted for this fence.",
                layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
            ) {
                Picker(
                    "",
                    selection: Binding(
                        get: { fence.altitudeReference },
                        set: {
                            var g = fence
                            g.altitudeReference = $0
                            fence = g
                        }
                    )
                ) {
                    ForEach(MissionGeofenceAltitudeReference.allCases) { r in
                        Text(r.displayTitle).tag(r)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if altitudeOrderWarning {
                Text("Max altitude must be greater than min altitude.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(GuardianSemanticColors.warningForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, GuardianSpacing.xs)
                    .padding(.horizontal, GuardianSpacing.sm)
                    .background(
                        GuardianSemanticColors.warningBackground,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
        }
    }
}

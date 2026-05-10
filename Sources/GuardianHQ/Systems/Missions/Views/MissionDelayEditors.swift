import SwiftUI

/// Value + unit row matching waypoint **Delay** controls (numeric field + unit menu). Used for task start / regularity delays in Missions, MC Setup, and postpone controls.
/// Parent rows should place a ``Spacer`` before this view so controls sit on the trailing edge (same pattern as other sidebar pickers).
struct MissionDelayValueUnitEditor: View {
    var label: String = ""
    @Binding var value: Double
    @Binding var unit: DelayUnit
    var minimumTotalSeconds: TimeInterval = 0
    /// When set, the numeric field and clamping never exceed this total (e.g. operator postpone cap).
    var maximumTotalSeconds: TimeInterval? = nil
    var numericFieldWidth: CGFloat = 96
    var unitPickerWidth: CGFloat = 72
    var labelColumnWidth: CGFloat = 78
    var secondaryLabelColor: Color
    var controlSize: ControlSize = .regular

    private var maxForUnit: Double {
        if let cap = maximumTotalSeconds {
            return MissionDelayPolicy.maxDisplayValue(for: unit, cappedAtTotalSeconds: cap)
        }
        return MissionDelayPolicy.maxDisplayValue(for: unit)
    }

    private var step: Double {
        switch unit {
        case .hrs: return 0.25
        case .mins: return 1
        case .secs: return 1
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryLabelColor)
                    .frame(width: labelColumnWidth, alignment: .leading)
            }
            StrictNumberField(
                value: Binding(
                    get: { value },
                    set: { newV in
                        value = MissionDelayPolicy.clampDisplayValue(
                            newV,
                            unit: unit,
                            minimumTotalSeconds: minimumTotalSeconds,
                            maximumTotalSeconds: maximumTotalSeconds
                        )
                    }
                ),
                step: step,
                min: 0,
                max: maxForUnit
            )
            .frame(width: numericFieldWidth)
            Picker("Unit", selection: $unit) {
                ForEach(DelayUnit.allCases) { u in
                    Text(u.missionDelayMenuLabel).tag(u)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: unitPickerWidth)
            .controlSize(controlSize)
            .onChange(of: unit) { newUnit in
                value = MissionDelayPolicy.clampDisplayValue(
                    value,
                    unit: newUnit,
                    minimumTotalSeconds: minimumTotalSeconds,
                    maximumTotalSeconds: maximumTotalSeconds
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Leading label + value/unit editor for Mission Control **Alter** controls (scheduled start / task deferrals).
struct MissionDelayPostponeValueUnitRow: View {
    var postponeLabel: String = "Alter"
    var postponeLabelColor: Color
    @Binding var value: Double
    @Binding var unit: DelayUnit
    var minimumTotalSeconds: TimeInterval = 1
    var maximumTotalSeconds: TimeInterval? = nil
    var numericFieldWidth: CGFloat = 88
    var unitPickerWidth: CGFloat = 68
    var controlSize: ControlSize = .small

    var body: some View {
        HStack(spacing: 8) {
            Text(postponeLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(postponeLabelColor)
            MissionDelayValueUnitEditor(
                label: "",
                value: $value,
                unit: $unit,
                minimumTotalSeconds: minimumTotalSeconds,
                maximumTotalSeconds: maximumTotalSeconds,
                numericFieldWidth: numericFieldWidth,
                unitPickerWidth: unitPickerWidth,
                labelColumnWidth: 0,
                secondaryLabelColor: postponeLabelColor.opacity(0.85),
                controlSize: controlSize
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

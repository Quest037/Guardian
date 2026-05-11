import SwiftUI

/// Mission workspace or MC-S roster — edit a map point (slug is system-managed; not edited here).
/// Position is adjusted on the staging map by **dragging the selected pin**; this drawer edits kind, scope, catchment, and closed state only.
struct MissionWorkspaceMissionPointEditDrawer: View {
    let missionPointID: UUID
    @Binding var mission: Mission
    let onStructuralChange: () -> Void
    let persist: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private let formLabelColumn: CGFloat = 140

    private var pointIndex: Int? {
        mission.missionPoints.firstIndex { $0.id == missionPointID }
    }

    var body: some View {
        Group {
            if let idx = pointIndex {
                ScrollView {
                    VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                        GuardianLabeledFormField(label: "Point", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Text(mission.missionPoints[idx].mapChipLabel)
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(label: "Kind", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Picker("", selection: Binding(
                                get: { mission.missionPoints[idx].kind },
                                set: { newKind in
                                    guard mission.missionPoints[idx].kind != newKind else { return }
                                    mission.missionPoints[idx].kind = newKind
                                    onStructuralChange()
                                    persist()
                                }
                            )) {
                                Text("Rally").tag(MissionPointKind.rally)
                                Text("Extraction").tag(MissionPointKind.extraction)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(label: "Scope", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Picker("Scope", selection: Binding(
                                get: { mission.missionPoints[idx].taskID },
                                set: {
                                    mission.missionPoints[idx].taskID = $0
                                    persist()
                                }
                            )) {
                                Text("Mission-wide").tag(UUID?.none)
                                ForEach(Array(mission.routeMacro.tasks.enumerated()), id: \.element.id) { _, t in
                                    let name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    Text(name.isEmpty ? "Task" : name).tag(Optional(t.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(label: "Catchment (m)", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            TextField(
                                "10",
                                value: Binding(
                                    get: { mission.missionPoints[idx].catchmentRadiusM },
                                    set: {
                                        mission.missionPoints[idx].catchmentRadiusM = MissionPoint.clampedCatchmentRadiusM($0)
                                        persist()
                                    }
                                ),
                                format: .number.precision(.fractionLength(0...1))
                            )
                            .textFieldStyle(.roundedBorder)
                            .guardianFormControlSizing()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(
                            label: "Closed",
                            subtitle: "When on, planners ignore this point.",
                            layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
                        ) {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { mission.missionPoints[idx].isClosed },
                                    set: {
                                        mission.missionPoints[idx].isClosed = $0
                                        persist()
                                    }
                                )
                            )
                            .labelsHidden()
                            .tint(GuardianSemanticColors.infoForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(GuardianSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("This map point is no longer in the mission.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .padding(GuardianSpacing.md)
            }
        }
    }
}

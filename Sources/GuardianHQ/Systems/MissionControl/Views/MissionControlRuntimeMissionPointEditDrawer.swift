import SwiftUI

/// MC-R operator edit for a **runtime** map point (run envelope — not the saved mission template).
/// Position is adjusted on the live map by **dragging the selected pin**; this drawer edits kind, scope, catchment, and closed state only.
struct MissionControlRuntimeMissionPointEditDrawer: View {
    let missionPointID: UUID
    @ObservedObject var run: MissionRunEnvironment
    let mission: Mission
    let onPersist: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private let formLabelColumn: CGFloat = 140

    private var pointIndex: Int? {
        run.runtimeMissionPoints.firstIndex { $0.id == missionPointID }
    }

    var body: some View {
        Group {
            if let idx = pointIndex {
                ScrollView {
                    VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                        GuardianLabeledFormField(label: "Point", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Text(run.runtimeMissionPoints[idx].mapChipLabel)
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(label: "Kind", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Picker("", selection: Binding(
                                get: { run.runtimeMissionPoints[idx].kind },
                                set: { newKind in
                                    guard run.runtimeMissionPoints[idx].kind != newKind else { return }
                                    _ = run.applyRuntimeMissionPointUpdate(id: missionPointID, source: "operator") {
                                        $0.kind = newKind
                                    }
                                    onPersist()
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
                                get: { run.runtimeMissionPoints[idx].taskID },
                                set: { newScope in
                                    _ = run.applyRuntimeMissionPointUpdate(id: missionPointID, source: "operator") {
                                        $0.taskID = newScope
                                    }
                                    onPersist()
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
                                    get: { run.runtimeMissionPoints[idx].catchmentRadiusM },
                                    set: { value in
                                        _ = run.applyRuntimeMissionPointUpdate(id: missionPointID, source: "operator") {
                                            $0.catchmentRadiusM = MissionPoint.clampedCatchmentRadiusM(value)
                                        }
                                        onPersist()
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
                                    get: { run.runtimeMissionPoints[idx].isClosed },
                                    set: { closed in
                                        _ = run.applyRuntimeMissionPointSetClosed(id: missionPointID, isClosed: closed, source: "operator")
                                        onPersist()
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
                Text("This map point is no longer on the run.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .padding(GuardianSpacing.md)
            }
        }
    }
}

import SwiftUI

/// Where a template geofence row lives: mission-wide list or one task’s ``MissionTask/geofences``.
enum MissionGeofenceTemplatePlacement: Hashable {
    case missionWide
    case taskScoped(UUID)
}

/// Mission workspace **Fences** tab — edit name, boundary, circle radius, and template scope.
/// Geometry is adjusted on the staging map (drag center / rim, polygon vertices / centroid, tap edges to add anchors).
struct MissionWorkspaceGeofenceEditDrawer: View {
    let fenceID: UUID
    @Binding var mission: Mission
    let onMovePlacement: (MissionGeofenceTemplatePlacement) -> Void
    let persist: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private let formLabelColumn: CGFloat = 140

    private func currentPlacement() -> MissionGeofenceTemplatePlacement? {
        if mission.missionGeofences.contains(where: { $0.id == fenceID }) {
            return .missionWide
        }
        for t in mission.routeMacro.tasks {
            if t.geofences.contains(where: { $0.id == fenceID }) {
                return .taskScoped(t.id)
            }
        }
        return nil
    }

    private func fenceBinding() -> Binding<MissionGeofence> {
        Binding(
            get: {
                if let i = mission.missionGeofences.firstIndex(where: { $0.id == fenceID }) {
                    return mission.missionGeofences[i]
                }
                for (ti, t) in mission.routeMacro.tasks.enumerated() {
                    if let fi = t.geofences.firstIndex(where: { $0.id == fenceID }) {
                        return mission.routeMacro.tasks[ti].geofences[fi]
                    }
                }
                return MissionGeofence(name: "", shape: .circle)
            },
            set: { newValue in
                if let i = mission.missionGeofences.firstIndex(where: { $0.id == fenceID }) {
                    mission.missionGeofences[i] = newValue
                } else {
                    for ti in mission.routeMacro.tasks.indices {
                        if let fi = mission.routeMacro.tasks[ti].geofences.firstIndex(where: { $0.id == fenceID }) {
                            mission.routeMacro.tasks[ti].geofences[fi] = newValue
                            break
                        }
                    }
                }
                persist()
            }
        )
    }

    var body: some View {
        Group {
            if currentPlacement() != nil {
                let fb = fenceBinding()
                ScrollView {
                    VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                        GuardianLabeledFormField(label: "Fence", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Text(fb.wrappedValue.name.isEmpty ? "Untitled" : fb.wrappedValue.name)
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(label: "Name", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            TextField(
                                "Fence name",
                                text: Binding(
                                    get: { fb.wrappedValue.name },
                                    set: {
                                        var g = fb.wrappedValue
                                        g.name = $0
                                        fb.wrappedValue = g
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .guardianFormControlSizing()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(label: "Boundary", layout: .inlineLeadingLabel(labelWidth: formLabelColumn)) {
                            Picker(
                                "",
                                selection: Binding(
                                    get: { fb.wrappedValue.boundary },
                                    set: {
                                        var g = fb.wrappedValue
                                        g.boundary = $0
                                        fb.wrappedValue = g
                                    }
                                )
                            ) {
                                ForEach(MissionGeofenceBoundaryKind.allCases) { kind in
                                    Text(kind.displayTitle).tag(kind)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if fb.wrappedValue.shape == .circle {
                            GuardianLabeledFormField(
                                label: "Radius (m)",
                                subtitle: "Drag the rim handle on the map for quick edits.",
                                layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
                            ) {
                                TextField(
                                    "150",
                                    value: Binding(
                                        get: { fb.wrappedValue.circleRadiusMeters },
                                        set: {
                                            var g = fb.wrappedValue
                                            g.circleRadiusMeters = max(1, $0)
                                            fb.wrappedValue = g
                                        }
                                    ),
                                    format: .number.precision(.fractionLength(0))
                                )
                                .textFieldStyle(.roundedBorder)
                                .guardianFormControlSizing()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                            Text("Altitude envelope")
                                .font(GuardianTypography.font(.subsectionTitleSemibold))
                                .foregroundStyle(theme.textPrimary)
                            Text(
                                "Vertical band for this fence (meters). Stored on the fence, not the whole mission."
                            )
                            .font(GuardianTypography.font(.denseCaption12Regular))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                            MissionGeofenceAltitudeEnvelopeSection(
                                fence: fb,
                                formLabelColumn: formLabelColumn
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        GuardianLabeledFormField(
                            label: "Scope",
                            subtitle: "Mission-wide applies to every task; task-scoped applies only while that task runs.",
                            layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
                        ) {
                            Picker(
                                "Scope",
                                selection: Binding(
                                    get: {
                                        currentPlacement() ?? .missionWide
                                    },
                                    set: { newPlacement in
                                        if newPlacement != currentPlacement() {
                                            onMovePlacement(newPlacement)
                                        }
                                    }
                                )
                            ) {
                                Text("Mission-wide").tag(MissionGeofenceTemplatePlacement.missionWide)
                                ForEach(Array(mission.routeMacro.tasks.enumerated()), id: \.element.id) { _, t in
                                    let name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    Text(name.isEmpty ? "Task" : name).tag(MissionGeofenceTemplatePlacement.taskScoped(t.id))
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if fb.wrappedValue.shape == .polygon {
                            let warnings = geofenceAuthoringWarningStrings(for: fb.wrappedValue)
                            GuardianLabeledFormField(
                                label: "Polygon",
                                subtitle: "Drag vertices or the square centroid on the map. Tap a boundary edge to insert a new vertex.",
                                layout: .inlineLeadingLabel(labelWidth: formLabelColumn)
                            ) {
                                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                                    Text("\(fb.wrappedValue.polygonVertices.count) vertices")
                                        .font(GuardianTypography.font(.denseCaption12Regular))
                                        .foregroundStyle(theme.textSecondary)
                                    if fb.wrappedValue.polygonVertices.count > 3 {
                                        GuardianThemedButton(
                                            accent: .neutral,
                                            surface: .outline,
                                            size: .small,
                                            shape: .cornered,
                                            contentSizing: .intrinsic,
                                            action: {
                                                var g = fb.wrappedValue
                                                guard g.polygonVertices.count > 3 else { return }
                                                g.polygonVertices.removeLast()
                                                fb.wrappedValue = g
                                            },
                                            label: { Text("Remove last vertex") }
                                        )
                                    }
                                    if !warnings.isEmpty {
                                        ForEach(Array(warnings.enumerated()), id: \.offset) { _, line in
                                            Text(line)
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
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(GuardianSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("This fence is no longer in the mission.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
                    .padding(GuardianSpacing.md)
            }
        }
    }

    private func geofenceAuthoringWarningStrings(for fence: MissionGeofence) -> [String] {
        let geo = Utilities.mission.geofenceGeometry
        switch fence.shape {
        case .polygon:
            if geo.polygonHasInsufficientVertices(fence.polygonVertices) {
                return ["Add at least three vertices for this polygon to draw on the map."]
            }
            if geo.polygonSelfIntersectsWGS84(vertices: fence.polygonVertices) {
                return ["Edges cross — adjust vertices so the boundary does not intersect itself."]
            }
            return []
        case .circle:
            return []
        }
    }
}

import SwiftUI

/// Viewport overlay for World Builder obstacle authoring (build mode).
/// Binds to ``WorldBuilderController/obstaclePlacementDraft`` — same buffer used for placement and for syncing a selected model.
struct WorldBuilderObstacleToolBar: View {
    @Binding var record: TrainingEnvironmentObstacleRecord
    let footZMinM: Double
    let footZMaxM: Double
    let theme: GuardianThemePalette
    /// Map placement mode (click to add); inactive while a placed model is selected.
    let placementActive: Bool
    let isEditingPlaced: Bool
    let obstacleCount: Int
    let isSyncInFlight: Bool
    let onClone: () -> Void
    let onDelete: () -> Void
    let onRepairMap: () -> Void
    let onClose: () -> Void

    private static let dimensionMinM = WorldBuilderObstacleManifestSupport.dimensionMinM
    private static let dimensionMaxM = WorldBuilderObstacleManifestSupport.dimensionMaxM
    private static let cuboidLengthMaxM = WorldBuilderObstacleManifestSupport.cuboidLengthMaxM
    private static let dimensionStepM = 0.25
    private static let yawMinDeg = -180.0
    private static let yawMaxDeg = 180.0
    private static let yawStepDeg = 1.0
    private static let footZStepM = 0.25
    private static let numericFieldWidth: CGFloat = 88
    private static let modeOutlineWidth: CGFloat = 3

    private enum PanelMode {
        case placing
        case editing
        case neutral
    }

    private var panelMode: PanelMode {
        if isEditingPlaced { return .editing }
        if placementActive { return .placing }
        return .neutral
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            header
            kindPicker
            modeCaption
            if isEditingPlaced {
                selectedObstacleActions
            }
            fields
            Text("\(obstacleCount) / \(TrainingEnvironmentObstacleRecord.maxCount) obstacles")
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textSecondary)
            GuardianThemedButton(
                accent: .neutral,
                surface: .outline,
                size: .small,
                action: onRepairMap,
                label: {
                    HStack(spacing: GuardianSpacing.xs) {
                        if isSyncInFlight {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSyncInFlight ? "Syncing models…" : "Sync models to list")
                    }
                }
            )
            .disabled(isSyncInFlight)
            .help("Remove stray models and rebuild obstacles to match this list")
            .guardianPointerOnHover()
        }
        .padding(GuardianSpacing.sm)
        .frame(maxWidth: 280)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: GuardianSpacing.xs))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianSpacing.xs)
                .stroke(panelOutlineColor, lineWidth: panelOutlineWidth)
        )
    }

    @ViewBuilder
    private var modeCaption: some View {
        Group {
            switch panelMode {
            case .editing:
                Text("Editing placed model — adjust settings below or drag on the map.")
            case .placing:
                Text("Click the map to place this model.")
            case .neutral:
                Text("Click a model on the map to edit it.")
            }
        }
        .font(GuardianTypography.Scale.caption.font())
        .foregroundStyle(theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var panelOutlineColor: Color {
        switch panelMode {
        case .placing:
            GuardianSemanticColors.successStroke
        case .editing:
            GuardianSemanticColors.warningStroke
        case .neutral:
            theme.borderSubtle
        }
    }

    private var panelOutlineWidth: CGFloat {
        switch panelMode {
        case .placing, .editing:
            Self.modeOutlineWidth
        case .neutral:
            1
        }
    }

    private var selectedObstacleActions: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            Text("Selected model")
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textTertiary)
            HStack(spacing: GuardianSpacing.xs) {
                GuardianThemedButton(
                    accent: .primary,
                    surface: .outline,
                    size: .small,
                    action: onClone,
                    label: {
                        Label("Clone", systemImage: "plus.square.on.square")
                            .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                    }
                )
                .help("Duplicate this model at the same position")
                .guardianPointerOnHover()
                GuardianThemedButton(
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    action: onDelete,
                    label: {
                        Label("Delete", systemImage: "trash")
                            .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                    }
                )
                .help("Remove this model from the world")
                .guardianPointerOnHover()
            }
        }
        .padding(GuardianSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: GuardianSpacing.xxs))
        .overlay(
            RoundedRectangle(cornerRadius: GuardianSpacing.xxs)
                .stroke(theme.borderSubtle, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: GuardianSpacing.xs) {
            Text("Models")
                .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(GuardianTypography.Scale.caption.font(weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(GuardianPointerPlainButtonStyle())
            .accessibilityLabel("Close model tools")
        }
    }

    /// Only operator changes to Type reset shape parameters — not selection sync from the map.
    private var kindSelection: Binding<TrainingEnvironmentObstacleKind> {
        Binding(
            get: { record.kind },
            set: { newKind in
                guard newKind != record.kind else { return }
                var updated = record
                updated.kind = newKind
                updated.applyDefaultParameters()
                record = updated
            }
        )
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Text("Type")
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textTertiary)
            Picker("Type", selection: kindSelection) {
                ForEach(TrainingEnvironmentObstacleKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var fields: some View {
        axisOrientationPicker
        usesAutoZToggle
        footZRow
        dimensionRow("Yaw (°)", value: $record.yawDeg, step: Self.yawStepDeg, min: Self.yawMinDeg, max: Self.yawMaxDeg)
        switch record.kind {
        case .cube:
            dimensionRow("Edge (m)", value: cubeEdgeBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
        case .cuboid:
            dimensionRow("Length (m)", value: cuboidLengthBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.cuboidLengthMaxM)
            dimensionRow("Width (m)", value: cuboidWidthBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
            dimensionRow("Height (m)", value: cuboidHeightBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
        case .cylinder:
            dimensionRow("Radius (m)", value: cylinderRadiusBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
            dimensionRow("Height (m)", value: cylinderHeightBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
        case .cone:
            dimensionRow("Radius (m)", value: coneRadiusBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
            dimensionRow("Height (m)", value: coneHeightBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
        case .pyramid:
            dimensionRow("Base width (m)", value: pyramidBaseWidthBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
            dimensionRow("Base depth (m)", value: pyramidBaseDepthBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
            dimensionRow("Height (m)", value: pyramidHeightBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
        case .toblerone:
            dimensionRow("Width (m)", value: tobleroneWidthBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
            dimensionRow("Length (m)", value: tobleroneLengthBinding, step: Self.dimensionStepM, min: Self.dimensionMinM, max: Self.dimensionMaxM)
        }
    }

    @ViewBuilder
    private var axisOrientationPicker: some View {
        if record.kind == .cylinder || record.kind == .toblerone {
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                Text("Orientation")
                    .font(GuardianTypography.Scale.caption.font())
                    .foregroundStyle(theme.textTertiary)
                Picker("Orientation", selection: $record.axisOrientation) {
                    ForEach(TrainingObstacleAxisOrientation.allCases) { axis in
                        Text(axis.displayName).tag(axis)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var usesAutoZToggle: some View {
        Toggle(isOn: $record.usesAutoZ) {
            Text("Snap to ground")
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textSecondary)
        }
        .toggleStyle(.switch)
        .help("When on, the bottom of the model rests on the map surface. Turn off to set foot height manually.")
    }

    private var footZRow: some View {
        dimensionRow(
            "Foot Z (m)",
            value: footZBinding,
            step: Self.footZStepM,
            min: footZMinM,
            max: footZMaxM
        )
        .disabled(record.usesAutoZ)
        .opacity(record.usesAutoZ ? 0.55 : 1)
        .help("Height of the model bottom relative to the map top (z = 0). The map block spans z = \(formatFootZHelp(footZMinM)) … 0 m.")
    }

    private var footZBinding: Binding<Double> {
        Binding(
            get: { WorldBuilderObstacleManifestSupport.footZM(for: record) },
            set: { foot in
                var updated = record
                updated.usesAutoZ = false
                WorldBuilderObstacleManifestSupport.setFootZM(foot, record: &updated)
                record = updated
            }
        )
    }

    private func formatFootZHelp(_ metres: Double) -> String {
        if metres == metres.rounded() && abs(metres) < 10_000 {
            return String(format: "%.0f", metres)
        }
        return String(format: "%.2f", metres)
    }

    private var cubeEdgeBinding: Binding<Double> {
        Binding(
            get: { record.cube?.edgeM ?? 2 },
            set: { value in
                var updated = record
                updated.setEdgeM(value)
                record = updated
            }
        )
    }

    private var cuboidLengthBinding: Binding<Double> {
        Binding(
            get: { record.cuboid?.lengthM ?? 3 },
            set: { value in
                var updated = record
                updated.setCuboidDimensions(lengthM: value)
                record = updated
            }
        )
    }

    private var cuboidWidthBinding: Binding<Double> {
        Binding(
            get: { record.cuboid?.widthM ?? 2 },
            set: { value in
                var updated = record
                updated.setCuboidDimensions(widthM: value)
                record = updated
            }
        )
    }

    private var cuboidHeightBinding: Binding<Double> {
        Binding(
            get: { record.cuboid?.heightM ?? 1.5 },
            set: { value in
                var updated = record
                updated.setCuboidDimensions(heightM: value)
                record = updated
            }
        )
    }

    private var cylinderRadiusBinding: Binding<Double> {
        Binding(
            get: { record.cylinder?.radiusM ?? 1 },
            set: { value in
                var updated = record
                updated.setCylinderDimensions(radiusM: value)
                record = updated
            }
        )
    }

    private var cylinderHeightBinding: Binding<Double> {
        Binding(
            get: { record.cylinder?.heightM ?? 3 },
            set: { value in
                var updated = record
                updated.setCylinderDimensions(heightM: value)
                record = updated
            }
        )
    }

    private var coneRadiusBinding: Binding<Double> {
        Binding(
            get: { record.cone?.radiusM ?? 1.5 },
            set: { value in
                var updated = record
                updated.setConeDimensions(radiusM: value)
                record = updated
            }
        )
    }

    private var coneHeightBinding: Binding<Double> {
        Binding(
            get: { record.cone?.heightM ?? 3 },
            set: { value in
                var updated = record
                updated.setConeDimensions(heightM: value)
                record = updated
            }
        )
    }

    private var pyramidBaseWidthBinding: Binding<Double> {
        Binding(
            get: { record.pyramid?.baseWidthM ?? 3 },
            set: { value in
                var updated = record
                updated.setPyramidDimensions(baseWidthM: value)
                record = updated
            }
        )
    }

    private var pyramidBaseDepthBinding: Binding<Double> {
        Binding(
            get: { record.pyramid?.baseDepthM ?? 3 },
            set: { value in
                var updated = record
                updated.setPyramidDimensions(baseDepthM: value)
                record = updated
            }
        )
    }

    private var pyramidHeightBinding: Binding<Double> {
        Binding(
            get: { record.pyramid?.heightM ?? 2.5 },
            set: { value in
                var updated = record
                updated.setPyramidDimensions(heightM: value)
                record = updated
            }
        )
    }

    private var tobleroneWidthBinding: Binding<Double> {
        Binding(
            get: { record.toblerone?.widthM ?? 3 },
            set: { value in
                var updated = record
                updated.setTobleroneDimensions(widthM: value)
                record = updated
            }
        )
    }

    private var tobleroneLengthBinding: Binding<Double> {
        Binding(
            get: { record.toblerone?.lengthM ?? 4 },
            set: { value in
                var updated = record
                updated.setTobleroneDimensions(lengthM: value)
                record = updated
            }
        )
    }

    private func dimensionRow(
        _ label: String,
        value: Binding<Double>,
        step: Double,
        min: Double,
        max: Double
    ) -> some View {
        HStack(spacing: GuardianSpacing.xs) {
            Text(label)
                .font(GuardianTypography.Scale.caption.font())
                .foregroundStyle(theme.textTertiary)
                .frame(width: 110, alignment: .leading)
            StrictNumberField(value: value, step: step, min: min, max: max)
                .frame(width: Self.numericFieldWidth)
        }
    }
}

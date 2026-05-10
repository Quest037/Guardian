import AppKit
import SwiftUI

/// Reusable calibration canvas — labelled vehicle image, status panel, and (when a preflight banner
/// is supplied) a top-of-modal preflight result block with remediation. The view itself is purely
/// presentational; running probes is the responsibility of the wrapping shell (modal/sidebar/inline).
struct VehicleCalibrationView: View {
    let vehicle: FleetVehicleModel
    /// Banner block rendered above the canvas (preflight running / last result, or nothing). Pass an
    /// `EmptyView()` (or omit) for views that do not run preflight (e.g. simple inline embeds).
    @ViewBuilder var preflightBanner: () -> AnyView

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSystemID: FleetCalibrationSystemID?

    init(
        vehicle: FleetVehicleModel,
        @ViewBuilder preflightBanner: @escaping () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.vehicle = vehicle
        self.preflightBanner = preflightBanner
    }

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var items: [FleetCalibrationItem] {
        vehicle.collections.calibration.items
    }

    private var selectedItem: FleetCalibrationItem? {
        selectedSystemID.flatMap { id in items.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preflightBanner()
            calibrationCanvas
            statusPanel
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var calibrationCanvas: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let imageSide = min(size.width * 0.59, size.height * 0.80)
            let imageRect = CGRect(
                x: (size.width - imageSide) / 2,
                y: (size.height - imageSide) / 2,
                width: imageSide,
                height: imageSide
            )

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(theme.backgroundRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(theme.borderSubtle.opacity(0.8), lineWidth: 1)
                    )

                SimulationDeviceThumbnail(imageBasenames: vehicle.data.vehicleType.defaultSimulationDeviceImageBasenames)
                    .frame(width: imageSide, height: imageSide)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
                    .position(x: imageRect.midX, y: imageRect.midY)

                if items.isEmpty {
                    emptyCalibrationOverlay
                } else {
                    ForEach(items) { item in
                        markerLine(for: item, imageRect: imageRect, size: size)
                    }

                    ForEach(items) { item in
                        markerLabel(for: item, size: size)
                    }
                }
            }
        }
        .frame(minHeight: 300, idealHeight: 390, maxHeight: 460)
    }

    private var emptyCalibrationOverlay: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            Text("No calibration telemetry yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Calibration markers appear as the vehicle reports health and sensor data.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .multilineTextAlignment(.center)
        .padding(18)
        .background(theme.backgroundElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
    }

    private func markerLine(for item: FleetCalibrationItem, imageRect: CGRect, size: CGSize) -> some View {
        let anchor = FleetCalibrationAnchorCatalog.anchor(for: item.id, vehicleType: vehicle.data.vehicleType)
        let start = CGPoint(
            x: imageRect.minX + (imageRect.width * anchor.imageAnchor.x),
            y: imageRect.minY + (imageRect.height * anchor.imageAnchor.y)
        )
        let end = CGPoint(x: size.width * anchor.labelPoint.x, y: size.height * anchor.labelPoint.y)
        let selected = selectedSystemID == item.id

        return ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(calibrationColor(for: item.status).opacity(selected ? 0.96 : 0.72), lineWidth: selected ? 3 : 2)

            Path { path in
                path.move(to: start)
                path.addLine(to: end)
            }
            .stroke(Color.clear, lineWidth: 16)
            .contentShape(Path { path in
                path.move(to: start)
                path.addLine(to: end)
            })
            .onTapGesture {
                selectedSystemID = item.id
            }
            .cursorPointer()

            Circle()
                .fill(calibrationColor(for: item.status))
                .frame(width: selected ? 10 : 8, height: selected ? 10 : 8)
                .position(start)
        }
    }

    private func markerLabel(for item: FleetCalibrationItem, size: CGSize) -> some View {
        let definition = FleetCalibrationExtensionRegistry.definition(for: item.id)
        let anchor = FleetCalibrationAnchorCatalog.anchor(for: item.id, vehicleType: vehicle.data.vehicleType)
        let selected = selectedSystemID == item.id

        return Button {
            selectedSystemID = item.id
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(calibrationColor(for: item.status))
                    .frame(width: 8, height: 8)
                Image(systemName: definition.iconSystemName)
                    .font(.system(size: 10, weight: .semibold))
                Text(definition.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.backgroundElevated)
                    if selected {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(calibrationColor(for: item.status).opacity(0.22))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(calibrationColor(for: item.status).opacity(selected ? 0.75 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .cursorPointer()
        .position(x: size.width * anchor.labelPoint.x, y: size.height * anchor.labelPoint.y)
    }

    @ViewBuilder
    private var statusPanel: some View {
        if let selectedItem {
            selectedStatusBlock(for: selectedItem)
        } else {
            unselectedStatusBlock
        }
    }

    /// Default status block when no calibration marker is selected. Two columns: a clickable hint on
    /// the left, a compact vehicle overview on the right so the modal never feels empty before the
    /// operator picks a system.
    private var unselectedStatusBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                    Text("Select a calibration marker")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                }
                Text("Click any line or label to inspect its message, remediation advice, and future manual calibration controls.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VehicleOverviewDigest(vehicle: vehicle)
                .frame(width: 260)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 14))
    }

    private func selectedStatusBlock(for item: FleetCalibrationItem) -> some View {
        let definition = FleetCalibrationExtensionRegistry.definition(for: item.id)
        let controls = FleetCalibrationExtensionRegistry.controls(for: item.id, vehicle: vehicle, item: item)
        let telemetryFields = FleetTelemetryFieldCatalog.fields(forSystem: item.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: definition.iconSystemName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(calibrationColor(for: item.status))
                VStack(alignment: .leading, spacing: 4) {
                    Text(definition.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(item.message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(calibrationColor(for: item.status))
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = item.technicalDetail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            // Two-column row: remediation steps on the left, system-specific live telemetry on the
            // right. Each side gets a sensible empty placeholder so the column never disappears
            // and the layout doesn't jiggle as fields drop in.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if let advice = item.remediationAdvice {
                        PreflightProbeRemediationBlock(advice: advice)
                    } else {
                        Text("No remediation needed.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                SystemTelemetryColumn(
                    fields: telemetryFields,
                    hub: vehicle.data.telemetry
                )
                .frame(width: 260, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 8) {
                if controls.isEmpty {
                    EmptyView()
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(controls.enumerated()), id: \.offset) { _, control in
                            control
                        }
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.backgroundRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(calibrationColor(for: item.status).opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func calibrationColor(for status: FleetCalibrationStatus) -> Color {
        switch status {
        case .green:
            return GuardianSemanticColors.successStroke
        case .warning:
            return GuardianSemanticColors.warningStroke
        case .error:
            return GuardianSemanticColors.dangerStroke
        }
    }
}

// MARK: - Per-system telemetry column

/// Right column inside the selected calibration system's status block. Renders the catalogued
/// fields for that system as `label  value` rows. When the system has zero catalogued fields, or
/// when every catalogued field returns `nil` against the live hub, shows a neutral placeholder.
private struct SystemTelemetryColumn: View {
    let fields: [FleetTelemetryFieldCatalog.Field]
    let hub: FleetHubVehicleTelemetry?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var rows: [(id: String, label: String, value: String)] {
        guard let hub else { return [] }
        return fields.compactMap { field in
            guard let v = field.format(hub) else { return nil }
            return (field.id, field.displayLabel, v)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Text("Live telemetry")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
            }

            if rows.isEmpty {
                Text("No additional telemetry fields available")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(rows, id: \.id) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 110, alignment: .leading)
                            Text(row.value)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.textPrimary.opacity(0.95))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.borderSubtle.opacity(0.8), lineWidth: 1)
                )
        )
    }
}

// MARK: - Vehicle overview digest

/// Compact at-a-glance digest shown when no calibration marker is selected. Surfaces the same
/// fields the old `VehicleTelemetryInfoSheet` Summary mode rendered, but as a always-on right
/// column so the modal is useful immediately on open instead of requiring a click.
private struct VehicleOverviewDigest: View {
    let vehicle: FleetVehicleModel

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var rows: [(label: String, value: String)] {
        let t = vehicle.data.telemetry
        let battery = vehicle.collections.operational.battery
        let gps = vehicle.collections.operational.gps
        let lifecycle = vehicle.collections.lifecycleStatus
        var out: [(String, String)] = [
            ("Short ID", vehicle.displayShortID),
            ("Class", vehicle.data.vehicleType.displayName),
            ("Autopilot", t?.autopilotStack.displayName ?? "—"),
            ("State", lifecycle.shortLabel),
            ("Mode", (t?.flightMode.isEmpty == false) ? (t?.flightMode ?? "—") : "—"),
            ("Armed", (t?.isArmed ?? false) ? "Yes" : "No"),
            ("Battery", battery.percent0to100.map { "\(Int(round($0)))%" } ?? "—"),
            ("GPS", gps.titleText.replacingOccurrences(of: "GPS ", with: "")),
        ]
        if let lat = t?.latitudeDeg, let lon = t?.longitudeDeg, lat.isFinite, lon.isFinite {
            out.append(("Position", String(format: "%.5f, %.5f", lat, lon)))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Text("Vehicle overview")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.uppercase)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 90, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.textPrimary.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.borderSubtle.opacity(0.8), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preflight banner

/// Banner shown above the canvas summarising the most recent preflight probe outcome on the FVM
/// (or the in-flight probe). Uses theme palette colours so it reads correctly in both light and
/// dark modes; failure cases reuse ``PreflightProbeRemediationBlock`` for the steps list.
struct VehicleCalibrationPreflightBanner: View {
    let entry: PreflightProbeHistoryEntry?
    let isRunning: Bool
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        if isRunning {
            runningBlock
        } else if let entry {
            resultBlock(entry: entry)
        } else {
            EmptyView()
        }
    }

    private var runningBlock: some View {
        bannerShell(strokeColor: GuardianSemanticColors.warningStroke, tint: GuardianSemanticColors.warningStroke) {
            HStack(alignment: .center, spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Running preflight check…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Sending arm command and watching the autopilot response.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func resultBlock(entry: PreflightProbeHistoryEntry) -> some View {
        let stroke = entry.result.passed
            ? GuardianSemanticColors.successStroke
            : GuardianSemanticColors.dangerStroke

        return bannerShell(strokeColor: stroke, tint: stroke) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: entry.result.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(stroke)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.result.passed ? "Preflight passed" : "Preflight failed")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                        Text(headerSubtitle(entry: entry))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss preflight result")
                }

                if !entry.result.passed, let advice = entry.result.remediationAdvice {
                    PreflightProbeRemediationBlock(advice: advice)
                } else if !entry.result.detail.isEmpty {
                    Text(entry.result.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func headerSubtitle(entry: PreflightProbeHistoryEntry) -> String {
        let relative = Self.relativeFormatter.localizedString(for: entry.recordedAt, relativeTo: Date())
        let detail = entry.result.passed
            ? "Arm probe completed"
            : entry.result.remediationAdvice?.summary ?? entry.result.detail
        return "\(detail) · \(relative)"
    }

    @ViewBuilder
    private func bannerShell<Inner: View>(
        strokeColor: Color,
        tint: Color,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.backgroundRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(tint.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(strokeColor.opacity(0.5), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Telemetry tab

/// Telemetry tab in the Vehicle Inspector. Chip strip + free-text search + grouped list rendered
/// off ``FleetTelemetryFieldCatalog``. Anything not catalogued falls through to the synthetic
/// "Other" chip via `FleetTelemetryFieldCatalog.unknownFields(in:)` so completeness is preserved.
struct VehicleTelemetryTabView: View {
    let vehicle: FleetVehicleModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeChip: FleetTelemetryFieldCatalog.Group? = nil
    @State private var searchText: String = ""

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlsBar
            Divider().opacity(0.2)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if visibleSections.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleSections, id: \.id) { section in
                            sectionView(section)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var controlsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                TextField("Search fields", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textPrimary)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.backgroundElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(theme.borderSubtle.opacity(0.7), lineWidth: 1)
                    )
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(label: "All", icon: "square.grid.2x2", group: nil)
                    ForEach(FleetTelemetryFieldCatalog.Group.allCases) { group in
                        chip(label: group.displayLabel, icon: group.iconSystemName, group: group)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func chip(
        label: String,
        icon: String,
        group: FleetTelemetryFieldCatalog.Group?
    ) -> some View {
        let active = activeChip == group
        return Button {
            activeChip = group
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(active ? Color.blue.opacity(0.18) : theme.backgroundElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(active ? Color.blue.opacity(0.7) : theme.borderSubtle.opacity(0.7), lineWidth: 1)
                    )
            )
            .foregroundStyle(active ? Color.blue : theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No telemetry matches that filter")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Clear the search box, pick another chip, or wait for the autopilot to start streaming the requested fields.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 12))
    }

    private struct Section: Identifiable {
        let id: String
        let title: String
        let icon: String
        let rows: [(id: String, label: String, value: String)]
    }

    private var visibleSections: [Section] {
        let hub = vehicle.data.telemetry ?? .empty
        let normalisedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var sections: [Section] = []

        for group in FleetTelemetryFieldCatalog.Group.allCases where group != .other {
            if let chipGroup = activeChip, chipGroup != group { continue }
            let groupFields = FleetTelemetryFieldCatalog.all.filter { $0.group == group }
            let rows: [(String, String, String)] = groupFields.compactMap { field in
                guard let v = field.format(hub) else { return nil }
                if !normalisedQuery.isEmpty,
                   !field.id.lowercased().contains(normalisedQuery),
                   !field.displayLabel.lowercased().contains(normalisedQuery) {
                    return nil
                }
                return (field.id, field.displayLabel, v)
            }
            if rows.isEmpty { continue }
            sections.append(Section(
                id: group.rawValue,
                title: group.displayLabel,
                icon: group.iconSystemName,
                rows: rows
            ))
        }

        if activeChip == nil || activeChip == .other {
            let unknowns = FleetTelemetryFieldCatalog.unknownFields(in: vehicle.data.telemetry ?? .empty)
            let filtered = unknowns.filter { row in
                guard !normalisedQuery.isEmpty else { return true }
                return row.id.lowercased().contains(normalisedQuery)
                    || row.displayLabel.lowercased().contains(normalisedQuery)
            }
            if !filtered.isEmpty {
                sections.append(Section(
                    id: FleetTelemetryFieldCatalog.Group.other.rawValue,
                    title: FleetTelemetryFieldCatalog.Group.other.displayLabel,
                    icon: FleetTelemetryFieldCatalog.Group.other.iconSystemName,
                    rows: filtered.map { ($0.id, $0.displayLabel, $0.value) }
                ))
            }
        }

        return sections
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Text(section.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.rows, id: \.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 240, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.textPrimary.opacity(0.95))
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Live wrappers

/// Live wrapper that resolves a fresh ``FleetVehicleModel`` from ``FleetLinkService`` on every
/// render so calibration views update automatically as telemetry arrives. Falls back to the
/// caller-supplied model when the link does not (yet) hold the vehicle (e.g. the row was
/// constructed locally inside the Vehicles grid before the bridge attached a sysid).
struct LiveVehicleCalibrationView: View {
    @ObservedObject var fleetLink: FleetLinkService
    let vehicleID: String
    let fallback: FleetVehicleModel?

    var body: some View {
        VehicleCalibrationView(vehicle: resolvedVehicle)
    }

    private var resolvedVehicle: FleetVehicleModel {
        if let live = fleetLink.vehicleModel(forVehicleID: vehicleID) {
            return live
        }
        if let fallback {
            return fallback
        }
        return FleetVehicleModel(vehicleID: vehicleID)
    }
}

struct VehicleCalibrationInlineView: View {
    @ObservedObject var fleetLink: FleetLinkService
    let vehicleID: String
    let fallback: FleetVehicleModel?

    init(fleetLink: FleetLinkService, vehicleID: String, fallback: FleetVehicleModel? = nil) {
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        self.fallback = fallback
    }

    var body: some View {
        LiveVehicleCalibrationView(fleetLink: fleetLink, vehicleID: vehicleID, fallback: fallback)
    }
}

/// "Vehicle Inspector" modal — segmented Calibration / Telemetry tabs. Calibration is the default
/// every time it opens; the Run preflight header button is only meaningful in the Calibration tab
/// so it is hidden on the Telemetry tab.
///
/// Persists preflight results on the FVM (capped at 3) via ``FleetLinkService.recordPreflightResult``
/// so re-opens of the modal show the previous outcome and the canvas keeps the failed-system marker
/// red until the next probe replaces it or the operator dismisses the banner.
struct VehicleCalibrationModal: View {
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var controlStore: MissionControlStore
    @ObservedObject var sitl: SitlService
    let vehicleID: String
    let fallback: FleetVehicleModel?

    @Environment(\.dismiss) private var dismiss
    @State private var isRunningPreflight = false
    @State private var activeTab: InspectorTab = .calibration

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case calibration = "Calibration"
        case telemetry = "Telemetry"
        var id: String { rawValue }
    }

    init(
        fleetLink: FleetLinkService,
        controlStore: MissionControlStore,
        sitl: SitlService,
        vehicleID: String,
        fallback: FleetVehicleModel? = nil
    ) {
        self.fleetLink = fleetLink
        self.controlStore = controlStore
        self.sitl = sitl
        self.vehicleID = vehicleID
        self.fallback = fallback
    }

    private var resolvedVehicle: FleetVehicleModel {
        if let live = fleetLink.vehicleModel(forVehicleID: vehicleID) { return live }
        if let fallback { return fallback }
        return FleetVehicleModel(vehicleID: vehicleID)
    }

    private var latestPreflight: PreflightProbeHistoryEntry? {
        resolvedVehicle.functions.preflightHistory.first
    }

    /// `true` when this vehicle's stream is currently bound to a `.running` / `.paused` / `.recovery`
    /// Mission Control run. Mirrors the gate in `MissionControlStore.runSingleVehiclePreflightProbe`
    /// so the Run preflight button shows "Preflight locked" before the API would refuse the call.
    private var isVehicleInLiveMission: Bool {
        controlStore.isVehicleStreamUsedInLiveMission(
            vehicleID: vehicleID,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    var body: some View {
        Modal(
            title: "Vehicle Inspector",
            subtitle: subtitle,
            headerActions: {
                Picker("", selection: $activeTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)

                if activeTab == .calibration {
                    preflightHeaderButton
                }

                GuardianThemedButton(
                    title: "Close",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: { dismiss() }
                )
                .keyboardShortcut(.cancelAction)
            },
            bodyContent: {
                Group {
                    switch activeTab {
                    case .calibration:
                        VehicleCalibrationView(
                            vehicle: resolvedVehicle,
                            preflightBanner: {
                                AnyView(
                                    VehicleCalibrationPreflightBanner(
                                        entry: latestPreflight,
                                        isRunning: isRunningPreflight,
                                        onDismiss: {
                                            fleetLink.clearPreflightHistory(vehicleID: vehicleID)
                                        }
                                    )
                                )
                            }
                        )
                    case .telemetry:
                        VehicleTelemetryTabView(vehicle: resolvedVehicle)
                    }
                }
            }
        )
        .frame(minWidth: 880, minHeight: 640)
    }

    @ViewBuilder
    private var preflightHeaderButton: some View {
        if isRunningPreflight {
            GuardianThemedButton(
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                isEnabled: false,
                action: {},
                label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Running…")
                    }
                }
            )
        } else if isVehicleInLiveMission {
            GuardianThemedButton(
                accent: .warning,
                surface: .outline,
                size: .small,
                shape: .cornered,
                isEnabled: false,
                action: {},
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                        Text("Preflight locked")
                    }
                }
            )
            .help("This vehicle is bound to an active Mission Control run. Mid-mission preflight (reserve swap-in, drone recovery, plugin auto-preflight) will be unlocked behind a deliberate operator override in a future build.")
        } else if let entry = latestPreflight {
            GuardianThemedButton(
                accent: entry.result.passed ? .success : .danger,
                surface: .outline,
                size: .small,
                shape: .cornered,
                action: runPreflight,
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: entry.result.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                        Text("Re-run preflight")
                    }
                }
            )
            .help("Run another preflight arm probe")
        } else {
            GuardianThemedButton(
                accent: .primary,
                surface: .solid,
                size: .small,
                shape: .cornered,
                action: runPreflight,
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                        Text("Run preflight")
                    }
                }
            )
            .help("Run a one-shot arm preflight probe and overlay the result on the calibration canvas.")
        }
    }

    private func runPreflight() {
        guard !isRunningPreflight else { return }
        guard !isVehicleInLiveMission else { return }
        isRunningPreflight = true
        Task { @MainActor in
            let result = await controlStore.runSingleVehiclePreflightProbe(
                vehicleID: vehicleID,
                fleetLink: fleetLink,
                sitl: sitl
            )
            fleetLink.recordPreflightResult(
                vehicleID: vehicleID,
                result: result,
                source: "calibrationModal.manual"
            )
            isRunningPreflight = false
        }
    }

    private var subtitle: String? {
        let vehicle = fleetLink.vehicleModel(forVehicleID: vehicleID) ?? fallback
        return vehicle?.displayShortID
    }
}

struct VehicleCalibrationSidebarPanel: View {
    @ObservedObject var fleetLink: FleetLinkService
    let vehicleID: String
    let fallback: FleetVehicleModel?

    init(fleetLink: FleetLinkService, vehicleID: String, fallback: FleetVehicleModel? = nil) {
        self.fleetLink = fleetLink
        self.vehicleID = vehicleID
        self.fallback = fallback
    }

    var body: some View {
        LiveVehicleCalibrationView(fleetLink: fleetLink, vehicleID: vehicleID, fallback: fallback)
            .padding(14)
    }
}

// MARK: - Cursor pointer modifier

private struct PointerCursorModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                guard !isHovering else { return }
                NSCursor.pointingHand.push()
                isHovering = true
            } else if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }
}

private extension View {
    func cursorPointer() -> some View {
        modifier(PointerCursorModifier())
    }
}

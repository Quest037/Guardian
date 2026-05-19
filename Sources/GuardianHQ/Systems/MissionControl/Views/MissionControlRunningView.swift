// MissionControlRunningView.swift — MC-R: live / paused run helpers (overview map identity, roster health card).
// Note: MC-R **Tasks** column chrome (``GuardianCard`` + overlay headers) lives on ``MissionRunDetailView`` in ``MissionControlSetupView.swift`` (`missionLiveTasksSideCard`).
import AppKit
import SwiftUI

/// Compact slot-state pill for MC-R roster rows, live console tiles, and task list (``MissionRunAssignmentSlotState/displayTitle`` + ``GuardianFeedbackSeverity``).
struct MissionControlRosterSlotAttentionCapsule: View {
    let severity: GuardianFeedbackSeverity
    let title: String
    /// Pointer-hover text; defaults to ``title`` when omitted.
    var help: String? = nil
    /// Tighter padding for MC-R task rows and live-console roster tiles (MCS accordion uses default ``false``).
    var compactMetrics: Bool = false

    private var resolvedHelp: String { help ?? title }

    private var horizontalPadding: CGFloat {
        compactMetrics ? GuardianSpacing.xxs : GuardianSpacing.xsTight
    }

    private var verticalPadding: CGFloat { compactMetrics ? 2 : 3 }

    var body: some View {
        Text(title)
            .font(GuardianTypography.font(.telemetryNano9Semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(severity.legacyTranslucentChipBackground)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(stroke.opacity(0.45), lineWidth: 1)
            )
            .help(resolvedHelp)
            .accessibilityLabel("Roster slot: \(title)")
            .modifier(RosterSlotAttentionDistinctHintModifier(hint: resolvedHelp == title ? nil : resolvedHelp))
    }

    private var foreground: Color {
        switch severity {
        case .success: GuardianSemanticColors.successForeground
        case .info: GuardianSemanticColors.infoForeground
        case .warning: GuardianSemanticColors.warningForeground
        case .error: GuardianSemanticColors.dangerForeground
        }
    }

    private var stroke: Color {
        switch severity {
        case .success: GuardianSemanticColors.successStroke
        case .info: GuardianSemanticColors.infoForeground
        case .warning: GuardianSemanticColors.warningStroke
        case .error: GuardianSemanticColors.dangerStroke
        }
    }
}

private struct RosterSlotAttentionDistinctHintModifier: ViewModifier {
    let hint: String?

    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

/// Layout helpers for ``MissionLiveVehicleHealthCard`` (MC-R live console roster rows and floating reserve pool picker).
enum MissionLiveVehicleHealthCardReservePoolPickerPolicy {
    /// MC-R health cards show the compact battery row when **percent** or **telemetry age** is known (same rule for roster and reserve pool strip).
    static func showCompactBattery(vehicleModel: FleetVehicleOperationalModel) -> Bool {
        vehicleModel.battery.percent0to100 != nil || vehicleModel.telemetryAgeS != nil
    }

    /// When the bracketed fleet short id already embeds ``FleetVehicleType/classCode`` (e.g. `[UGV-W:2]`), the neutral class pill beside the title is redundant in pool picker chrome.
    static func showReservePoolClassCapsule(bracketedVehicleShortID: String, vehicleClassCode: String) -> Bool {
        let id = bracketedVehicleShortID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id == "—" || id.isEmpty { return true }
        let code = vehicleClassCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { return true }
        return !id.contains("[\(code):")
    }
}

private struct MissionLiveVehicleHealthCardAccessibility: ViewModifier {
    let summary: String?
    let hint: String?
    let isButton: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let summary {
            if let hint, !hint.isEmpty {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    .accessibilityHint(hint)
                    .accessibilityAddTraits(isButton ? .isButton : [])
            } else {
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    .accessibilityAddTraits(isButton ? .isButton : [])
            }
        } else {
            content
        }
    }
}

/// Stable identity for the MC-R **live overview** map topology (home, paths, task focus, roster/pool **row** ids,
/// mission-point metadata). When ``focusedTaskID`` is set, ``allTasksCoords`` / ``taskPathIDs`` list only that task’s polyline.
/// **Excludes** live GPS / heading / mission-point coordinates — those are pushed
/// through ``MissionRunDetailView/liveOverviewMapMarkerCoordinateDigest`` + marker-only refresh so Leaflet
/// markers are not torn down on every hub tick. The map **view shell** matches MCS (``GuardianCard`` media +
/// same bridge hooks as roster staging); only this identity + live push functions differ.
struct LiveOverviewMapStructureIdentity: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let allTasksCoords: [[RouteCoordinate]]
    let taskPathIDs: [UUID]
    /// When set, the MC‑R overview map isolates clutter to this task (paths, map pins, roster vehicles, pool rows).
    /// Driven only by this run’s ``MissionRunEnvironment/operatorDisplaySettings/isolateLiveMapToSelectedTask`` (not ``GeneralSettingsStore``).
    let focusedTaskID: UUID?
    /// Rally / extraction pins: id, kind, closed, and map selection — not lat/lon.
    let missionPointTopologySignature: String
    /// Roster + floating reserve **row topology** on the live map (assignment ids and `task|poolSlot` ids only).
    /// Intentionally omits fleet tokens / bridge stream keys so reserve swap-in does not force a full map rebuild
    /// (marker churn follows ``liveOverviewMapMarkerCoordinateDigest``).
    let rosterSlotBindingSignature: String
    /// Mirrors ``MissionRunOperatorDisplaySettings/showMissionGeofencesOnMap`` so toggling fence visibility rebuilds Leaflet geofence layers.
    let showMissionGeofencesOnMap: Bool
    /// Fingerprint of template geofence ids so edits to fence geometry refresh the map without hub churn.
    let missionGeofenceTemplateTopologySignature: String
    /// Run-only augmentation (mission / task map / slot policies) so MC maps refresh when the run envelope changes.
    let missionControlRunGeofenceAugmentationTopologySignature: String
}

struct MissionLiveVehicleHealthCard: View {
    /// Fixed cap for roster tile width in the MC-R live console grid.
    private static let rosterCardMaxWidth: CGFloat = 300

    let slotTitle: String
    /// Same text as roster slot subtitle (`roleType` · position hint, or "—").
    let rosterSubtitle: String
    /// Imported brain label for this vehicle class (`displayName · vN`), when bound on the run.
    var brainBindingCaption: String? = nil
    /// Canonical short stream label with brackets (e.g. `[UAV-C:1]`); `—` when unresolved.
    let bracketedVehicleShortID: String
    let vehicleID: String?
    let simulationImageBasenames: [String]?
    /// Bundled device art when ``simulationImageBasenames`` is nil (live link / unknown sim art).
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    let vehicleModel: FleetVehicleOperationalModel
    /// Single-card vertical footprint (two text rows + thumbnail; no separate ID row).
    var slotHeight: CGFloat = 56
    /// Optional click-through; when non-nil the entire card becomes a button (used to open the
    /// MC-R vehicle overlay on the Tasks card). The empty-roster placeholder leaves this nil.
    var onTap: (() -> Void)?
    /// Worst merged slot attention for this roster row (MC-R live console); `nil` hides the pill.
    var slotAttention: (severity: GuardianFeedbackSeverity, title: String, help: String)? = nil
    /// When ``slotAttention`` is set, use tighter capsule padding in the fixed-height roster tile.
    var slotAttentionCapsuleCompact: Bool = true
    /// When true (MC-R **reserve pool swap** pick list): neutral **class** capsule beside the title when the bracketed id does not already encode class.
    var reservePoolPickerChrome: Bool = false
    /// Overrides button `.help` when set (e.g. reserve **browse** vs swap **pick**).
    var tapHelp: String? = nil
    /// When set, the card is exposed as a single VoiceOver element with this label (swap / browse pool context).
    var accessibilitySummary: String? = nil
    var accessibilityHint: String? = nil
    /// MC-R live roster: vehicle overlay is open for this slot (matches map selection ring).
    var isFocusedInLiveConsole: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var cardFill: Color { theme.backgroundElevated }
    private var cardStrokeNeutral: Color { theme.borderSubtle }

    private var showCompactBattery: Bool {
        MissionLiveVehicleHealthCardReservePoolPickerPolicy.showCompactBattery(vehicleModel: vehicleModel)
    }

    private var resolvedTapHelp: String {
        if let h = tapHelp { return h }
        return reservePoolPickerChrome ? "Select this reserve" : "Open vehicle details"
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardBody
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .guardianPointerOnHover()
                .help(resolvedTapHelp)
            } else {
                cardBody
            }
        }
        .frame(maxWidth: Self.rosterCardMaxWidth, alignment: .leading)
        .modifier(
            MissionLiveVehicleHealthCardAccessibility(
                summary: accessibilitySummary,
                hint: accessibilityHint,
                isButton: onTap != nil
            )
        )
    }

    private var cardBody: some View {
        /// Minimum square edge so tiny slot heights still show usable art; main roster and pool rows both use a **square** thumb (no tall narrow stamp).
        let thumbMinimumSide: CGFloat = 28
        let verticalPad = GuardianSpacing.xsTight * 2
        let thumbnailSide = max(thumbMinimumSide, slotHeight - verticalPad)
        let thumbW = thumbnailSide
        let thumbH = thumbnailSide
        return HStack(alignment: .center, spacing: GuardianSpacing.xs) {
            vehicleThumbnailColumn(width: thumbW, height: thumbH)
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    Text(slotTitle)
                        .font(GuardianTypography.font(.denseCaption12Medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if reservePoolPickerChrome,
                       MissionLiveVehicleHealthCardReservePoolPickerPolicy.showReservePoolClassCapsule(
                        bracketedVehicleShortID: bracketedVehicleShortID,
                        vehicleClassCode: vehicleClassForBundledDeviceArt.classCode
                       ) {
                        reservePoolPickerClassCapsule
                    }
                    if let slotAttention {
                        MissionControlRosterSlotAttentionCapsule(
                            severity: slotAttention.severity,
                            title: slotAttention.title,
                            help: slotAttention.help,
                            compactMetrics: slotAttentionCapsuleCompact
                        )
                    }
                    Spacer(minLength: GuardianSpacing.xs)
                    Text(bracketedVehicleShortID)
                        .font(GuardianTypography.font(.telemetryMono10Semibold))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .help(vehicleID.map { "Bridge vehicle key: \($0)" } ?? "No bridge vehicle key")
                }
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(rosterSubtitle)
                            .font(GuardianTypography.font(.denseCaption10Regular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let brainBindingCaption {
                            Text(brainBindingCaption)
                                .font(GuardianTypography.font(.denseCaption10Regular))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                    if showCompactBattery {
                        HStack(alignment: .center, spacing: GuardianSpacing.xxs) {
                            Image(systemName: batterySymbol)
                                .font(GuardianTypography.font(.denseCaption10Semibold))
                                .foregroundStyle(vehicleModel.battery.trafficBand.trafficLightIconTint)
                            Text(vehicleModel.battery.compactPercentLabel)
                                .font(GuardianTypography.font(.denseCaption10Semibold))
                                .foregroundStyle(theme.textSecondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        .help(batteryHoverText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: Self.rosterCardMaxWidth, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, GuardianSpacing.denseGutter)
        .padding(.vertical, GuardianSpacing.xsTight)
        .frame(maxWidth: Self.rosterCardMaxWidth, minHeight: slotHeight, maxHeight: slotHeight, alignment: .leading)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(lifecycleBorderColor, lineWidth: 1.6)
        )
        .overlay {
            if isFocusedInLiveConsole {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.55), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
    }

    private func vehicleThumbnailColumn(width: CGFloat, height: CGFloat) -> some View {
        let inset: CGFloat = 3
        let innerW = max(1, width - inset * 2)
        let innerH = max(1, height - inset * 2)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.07, green: 0.12, blue: 0.14),
                            Color(red: 0.05, green: 0.07, blue: 0.09),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            SimulationDeviceThumbnail(imageBasenames: liveThumbnailBasenames)
                .frame(width: innerW, height: innerH)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var liveThumbnailBasenames: [String] {
        if let names = simulationImageBasenames, !names.isEmpty { return names }
        return vehicleClassForBundledDeviceArt.defaultSimulationDeviceImageBasenames
    }

    private var batterySymbol: String {
        vehicleModel.battery.compactTelemetryBatterySymbolName
    }

    private var batteryHoverText: String {
        vehicleModel.battery.compactHoverHelpSummary
    }

    private var lifecycleBorderColor: Color {
        if let lifecycleStatus = vehicleModel.lifecycleStatus {
            return lifecycleStatus.color.uiColor.opacity(0.72)
        }
        return cardStrokeNeutral
    }

    private var reservePoolPickerClassCapsule: some View {
        Text(vehicleClassForBundledDeviceArt.classCode)
            .font(GuardianTypography.font(.telemetryNano9Semibold))
            .foregroundStyle(GuardianSemanticColors.neutralBadgeForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, GuardianSpacing.xsTight)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(GuardianSemanticColors.neutralBadgeBackground)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(theme.borderSubtle.opacity(0.45), lineWidth: 1)
            )
            .help(vehicleClassForBundledDeviceArt.displayName)
            .accessibilityLabel("Vehicle class \(vehicleClassForBundledDeviceArt.classCode)")
    }
}

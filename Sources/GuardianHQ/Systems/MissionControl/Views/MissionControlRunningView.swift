// MissionControlRunningView.swift — MC-R: live / paused run helpers (overview map identity, roster health card).
// Note: MC-R **Tasks** column chrome (``GuardianCard`` + overlay headers) lives on ``MissionRunDetailView`` in ``MissionControlSetupView.swift`` (`missionLiveTasksSideCard`).
import AppKit
import SwiftUI

/// Stable identity for the MC-R **live overview** map topology (home, paths, task focus, roster bindings,
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
    /// When set, map vehicle markers are restricted to this task’s roster (same as MC-R roster filter).
    let focusedTaskID: UUID?
    /// Rally / extraction pins: id, kind, closed, and map selection — not lat/lon.
    let missionPointTopologySignature: String
    /// Roster slots + floating reserve pool rows on the live map: assignment / slot ids + fleet binding keys — not live coordinates.
    let rosterSlotBindingSignature: String
}

struct MissionLiveVehicleHealthCard: View {
    /// Fixed cap for roster tile width in the MC-R live console grid.
    private static let rosterCardMaxWidth: CGFloat = 300

    let slotTitle: String
    /// Same text as roster slot subtitle (`roleType` · position hint, or "—").
    let rosterSubtitle: String
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

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var cardFill: Color { theme.backgroundElevated }
    private var cardStrokeNeutral: Color { theme.borderSubtle }

    private var showCompactBattery: Bool {
        vehicleModel.telemetryAgeS != nil
    }

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardBody
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .help("Open vehicle details")
            } else {
                cardBody
            }
        }
        .frame(maxWidth: Self.rosterCardMaxWidth, alignment: .leading)
    }

    private var cardBody: some View {
        let thumbColumnWidth: CGFloat = 28
        let verticalPad = GuardianSpacing.xsTight * 2
        let thumbnailStackHeight = max(thumbColumnWidth, slotHeight - verticalPad)
        return HStack(alignment: .center, spacing: GuardianSpacing.xs) {
            vehicleThumbnailColumn(width: thumbColumnWidth, height: thumbnailStackHeight)
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    Text(slotTitle)
                        .font(GuardianTypography.font(.denseCaption12Medium))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: GuardianSpacing.xs)
                    Text(bracketedVehicleShortID)
                        .font(GuardianTypography.font(.telemetryMono10Semibold))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .help(vehicleID.map { "Bridge vehicle key: \($0)" } ?? "No bridge vehicle key")
                }
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    Text(rosterSubtitle)
                        .font(GuardianTypography.font(.denseCaption10Regular))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if showCompactBattery {
                        Image(systemName: batterySymbol)
                            .font(GuardianTypography.font(.denseCaption10Semibold))
                            .foregroundStyle(vehicleModel.battery.trafficBand.trafficLightIconTint)
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
}

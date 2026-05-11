// MissionControlRunningView.swift — MC-R: live / paused run helpers (overview map signature, roster health card).
// Note: MC-R **Tasks** column chrome (``GuardianCard`` + overlay headers) lives on ``MissionRunDetailView`` in ``MissionControlSetupView.swift`` (`missionLiveTasksSideCard`).
import AppKit
import SwiftUI

struct LiveOverviewMapSignature: Equatable {
    let missionID: UUID?
    let homeCoord: RouteCoordinate?
    let allTasksCoords: [[RouteCoordinate]]
    let markers: [MapVehicleMarker]
    /// When set, map vehicle markers are restricted to this task’s roster (same as MC-R roster filter).
    let focusedTaskID: UUID?
}

struct MissionLiveVehicleHealthCard: View {
    let slotTitle: String
    /// Same text as roster slot subtitle (`roleType` · position hint, or "—").
    let rosterSubtitle: String
    let vehicleID: String?
    let simulationImageBasenames: [String]?
    /// Bundled device art when ``simulationImageBasenames`` is nil (live link / unknown sim art).
    let vehicleClassForBundledDeviceArt: FleetVehicleType
    let vehicleModel: FleetVehicleOperationalModel
    /// Must match the MC-R live roster row height so cards do not overflow and overlap siblings.
    var slotHeight: CGFloat = 210
    /// Optional click-through; when non-nil the entire card becomes a button (used to open the
    /// MC-R vehicle overlay on the Tasks card). The empty-roster placeholder leaves this nil.
    var onTap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var cardFill: Color { theme.backgroundElevated }
    private var cardStrokeNeutral: Color { theme.borderSubtle }

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
    }

    private var cardBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
                HStack(alignment: .center, spacing: GuardianSpacing.xs) {
                    vehicleTypeThumbnail
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: GuardianSpacing.titleStackTight) {
                        Text(slotTitle)
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                        Text(rosterSubtitle)
                            .font(GuardianTypography.font(.denseCaption10Regular))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let vehicleID {
                    Text(displayVehicleID(vehicleID))
                        .font(GuardianTypography.font(.telemetryMono9Regular))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .help("Bridge vehicle key: \(vehicleID)")
                }

                if vehicleModel.telemetryAgeS != nil {
                    Divider().opacity(0.22)
                    Spacer(minLength: 0)
                    batteryGpsMovementRow
                } else {
                    Spacer(minLength: 0)
                    Text("No telemetry")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(GuardianSpacing.denseGutter)
            .padding(.trailing, GuardianSpacing.floatingTrailingReserve)

            Color.clear
                .frame(width: 28, height: 28)
                .padding(.top, GuardianSpacing.xsTight)
                .padding(.trailing, GuardianSpacing.xsTight)
                .accessibilityLabel("Vehicle actions, coming soon")
        }
        .frame(width: 216, height: slotHeight)
        .background(cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(lifecycleBorderColor, lineWidth: 1.6)
        )
    }

    private var liveThumbnailBasenames: [String] {
        if let names = simulationImageBasenames, !names.isEmpty { return names }
        return vehicleClassForBundledDeviceArt.defaultSimulationDeviceImageBasenames
    }

    private var vehicleTypeThumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
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
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(GuardianSpacing.titleStackTight)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var batteryGpsMovementRow: some View {
        HStack(alignment: .bottom, spacing: GuardianSpacing.denseGutter) {
            VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                HStack(alignment: .bottom, spacing: GuardianSpacing.xsTight) {
                    Image(systemName: batterySymbol)
                        .font(GuardianTypography.font(.heroTimer30Bold))
                        .foregroundStyle(batteryIconTint(percent: vehicleModel.battery.percent0to100))
                        .help(batteryHoverText)
                    Text(batteryPercentText)
                        .font(GuardianTypography.font(.telemetryMono14Semibold))
                        .foregroundStyle(theme.textPrimary.opacity(0.94))
                        .lineLimit(1)
                }
                Text(vehicleModel.battery.trendText)
                    .font(GuardianTypography.font(.telemetryMono10Regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(vehicleModel.battery.etaText)
                    .font(GuardianTypography.font(.telemetryMono10Regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(theme.borderSubtle.opacity(0.9))
                .frame(width: 1, height: 58)

            VStack(alignment: .trailing, spacing: GuardianSpacing.xxs) {
                Text(vehicleModel.gps.titleText)
                    .font(GuardianTypography.font(.telemetryMono11Semibold))
                    .foregroundStyle(theme.textPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(vehicleModel.movement.titleText)
                    .font(GuardianTypography.font(.telemetryMono10Regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func batteryIconTint(percent: Double?) -> Color {
        guard let p = percent else {
            return Color.gray.opacity(0.55)
        }
        if p < 10 {
            return Color.red.opacity(0.92)
        }
        if p < 80 {
            return Color.yellow.opacity(0.95)
        }
        return GuardianSemanticColors.successForeground
    }

    private var batteryPercentText: String {
        guard let p = vehicleModel.battery.percent0to100 else { return "—" }
        return "\(Int(round(p)))%"
    }

    private var batterySymbol: String {
        if vehicleModel.battery.isCharging {
            return "battery.100.bolt"
        }
        return "battery.100"
    }

    private var batteryHoverText: String {
        let pct = batteryPercentText
        let v = vehicleModel.battery.voltageV.map { String(format: "%.1f V", $0) } ?? "—"
        let a = vehicleModel.battery.currentA.map { String(format: "%.1f A", $0) } ?? "—"
        let eta = vehicleModel.battery.etaText
        return "Battery \(pct), \(v), \(a), \(eta)"
    }

    private var lifecycleBorderColor: Color {
        if let lifecycleStatus = vehicleModel.lifecycleStatus {
            return lifecycleStatus.color.uiColor.opacity(0.72)
        }
        return cardStrokeNeutral
    }

    private func displayVehicleID(_ raw: String) -> String {
        if raw.hasPrefix("sysid:") {
            return String(raw.dropFirst("sysid:".count))
        }
        return raw
    }
}

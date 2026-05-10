// MissionControlRunningView.swift — MC-R: live / paused run helpers (overview map signature, roster health card).
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

    private let cardFill = GuardianDynamicColors.backgroundElevated
    private let cardStrokeNeutral = GuardianDynamicColors.borderSubtle

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    cardBody
                }
                .buttonStyle(.plain)
                .help("Open vehicle details")
            } else {
                cardBody
            }
        }
    }

    private var cardBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    vehicleTypeThumbnail
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(slotTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(GuardianDynamicColors.textPrimary)
                            .lineLimit(1)
                        Text(rosterSubtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(GuardianDynamicColors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if let vehicleID {
                    Text(displayVehicleID(vehicleID))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textTertiary)
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(GuardianDynamicColors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .padding(.trailing, 26)

            Color.clear
                .frame(width: 28, height: 28)
                .padding(.top, 6)
                .padding(.trailing, 6)
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
                .padding(3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var batteryGpsMovementRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 6) {
                    Image(systemName: batterySymbol)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(batteryIconTint(percent: vehicleModel.battery.percent0to100))
                        .help(batteryHoverText)
                    Text(batteryPercentText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.94))
                        .lineLimit(1)
                }
                Text(vehicleModel.battery.trendText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(vehicleModel.battery.etaText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(GuardianDynamicColors.borderSubtle.opacity(0.9))
                .frame(width: 1, height: 58)

            VStack(alignment: .trailing, spacing: 4) {
                Text(vehicleModel.gps.titleText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textPrimary.opacity(0.92))
                    .lineLimit(1)
                Text(vehicleModel.movement.titleText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(GuardianDynamicColors.textSecondary)
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

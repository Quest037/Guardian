import SwiftUI

/// Slide-in panel listing fleet vehicles (same chrome as `SimulationVehiclePickerSidebar`).
struct MissionRosterVehiclePickerSidebar: View {
    let vehicles: [MissionPickableFleetVehicle]
    let rowIsEnabled: (MissionPickableFleetVehicle) -> Bool
    let rowDisabledReason: (MissionPickableFleetVehicle) -> String?
    let onSelect: (MissionPickableFleetVehicle) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("Assign vehicle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.backgroundElevated)

            if vehicles.isEmpty {
                Spacer()
                Text("No vehicles in the fleet. Add a live link or spawn a sim from Vehicles.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(24)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(vehicles) { vehicle in
                            vehicleRow(vehicle)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private func vehicleRow(_ vehicle: MissionPickableFleetVehicle) -> some View {
        let enabled = rowIsEnabled(vehicle)
        let reason = rowDisabledReason(vehicle)
        return Button {
            if enabled {
                onSelect(vehicle)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 14) {
                        vehicleThumbnail(vehicle)
                            .frame(width: 72, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .opacity(enabled ? 1 : 0.45)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(vehicle.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(enabled ? theme.textPrimary : theme.textSecondary)
                                .multilineTextAlignment(.leading)
                            Text(vehicle.lifecycleStatus.mediumLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(vehicle.lifecycleStatus.color.uiColor.opacity(enabled ? 0.95 : 0.55))
                                .lineLimit(1)
                            Text(vehicle.vehicleShortID)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 8) {
                        FleetAutopilotStackBadge(stack: vehicle.autopilotStack)
                        FleetLiveSimBadge(isSimulation: vehicle.isSimulation)
                    }
                }

                if !enabled, let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GuardianSemanticColors.warningStroke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(vehicle.lifecycleStatus.color.uiColor.opacity(enabled ? 0.7 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func vehicleThumbnail(_ vehicle: MissionPickableFleetVehicle) -> some View {
        if let names = vehicle.simulationImageBasenames, !names.isEmpty {
            SimulationDeviceThumbnail(imageBasenames: names)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.35))
            }
        }
    }
}

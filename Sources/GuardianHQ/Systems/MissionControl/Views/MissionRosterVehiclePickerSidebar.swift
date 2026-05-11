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
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text("Assign vehicle")
                    .font(GuardianTypography.font(.hudTitle16Bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: GuardianSpacing.xs)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(GuardianTypography.font(.heroGlyph18Medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(GuardianPointerPlainButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Close")
            }
            .padding(.horizontal, GuardianSpacing.md)
            .padding(.vertical, GuardianSpacing.cardBodyInset)
            .background(theme.backgroundElevated)

            if vehicles.isEmpty {
                Spacer()
                Text("No vehicles in the fleet. Add a live link or spawn a sim from Vehicles.")
                    .font(GuardianTypography.font(.denseSubsection13Regular))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(GuardianSpacing.xl)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: GuardianSpacing.denseGutter) {
                        ForEach(vehicles) { vehicle in
                            vehicleRow(vehicle)
                        }
                    }
                    .padding(GuardianSpacing.md)
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
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: GuardianSpacing.cardBodyInset) {
                        vehicleThumbnail(vehicle)
                            .frame(width: 72, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .opacity(enabled ? 1 : 0.45)

                        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                            Text(vehicle.title)
                                .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                                .foregroundStyle(enabled ? theme.textPrimary : theme.textSecondary)
                                .multilineTextAlignment(.leading)
                            Text(vehicle.lifecycleStatus.mediumLabel)
                                .font(GuardianTypography.font(.formFieldLabel))
                                .foregroundStyle(vehicle.lifecycleStatus.color.uiColor.opacity(enabled ? 0.95 : 0.55))
                                .lineLimit(1)
                            Text(vehicle.vehicleShortID)
                                .font(GuardianTypography.font(.telemetryMono10Medium))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }

                    HStack(spacing: GuardianSpacing.xs) {
                        FleetAutopilotStackBadge(stack: vehicle.autopilotStack)
                        FleetLiveSimBadge(isSimulation: vehicle.isSimulation)
                    }
                }

                if !enabled, let reason, !reason.isEmpty {
                    Text(reason)
                        .font(GuardianTypography.font(.denseCaption10Medium))
                        .foregroundStyle(GuardianSemanticColors.warningStroke)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(GuardianSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(vehicle.lifecycleStatus.color.uiColor.opacity(enabled ? 0.7 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
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
                    .font(GuardianTypography.font(.heroGlyph28Medium))
                    .foregroundStyle(theme.textPrimary.opacity(0.35))
            }
        }
    }
}

import SwiftUI

/// Drawer: size tier + garage-style vehicle class cards (same pattern as Vehicles → Add sim).
struct TrainingLabAddVehicleDrawerContent: View {
    @ObservedObject var roster: TrainingLabRosterController
    @ObservedObject var fleetLink: FleetLinkService
    @Binding var simulationPlatform: SimulationPlatform
    let vehicleClassForTier: FleetVehicleType
    let controlsLocked: Bool
    let wingmanToSquadID: UUID?
    let onAdded: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var sizeTier: VehicleSizeTier = .medium

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ScrollView {
                VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                    if !fleetLink.isSimulateEnabled {
                        Text("Turn on Simulate in the top bar before adding vehicles.")
                            .font(GuardianTypography.font(.denseFootnoteRegular))
                            .foregroundStyle(GuardianSemanticColors.warningForeground)
                    }

                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text("Size tier")
                            .font(GuardianTypography.font(.formFieldLabel))
                            .foregroundStyle(theme.textSecondary)
                        VehicleSizeTierField(
                            vehicleClass: vehicleClassForTier,
                            tier: $sizeTier
                        )
                        .disabled(controlsLocked)
                    }

                    VStack(spacing: GuardianSpacing.denseGutter) {
                        ForEach(SimulationVehiclePreset.allCases) { preset in
                            if TrainingVehicleClass.fromSimulationPreset(preset) != nil {
                                vehicleCard(preset)
                            }
                        }
                    }
                }
                .padding(GuardianSpacing.md)
            }
        }
        .onAppear {
            sizeTier = VehicleClassSizeCatalogue.defaultTier(for: vehicleClassForTier)
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: GuardianSpacing.sm) {
            Text("Add vehicle")
                .font(GuardianTypography.font(.hudTitle16Bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: GuardianSpacing.xs)
            Picker("Stack", selection: $simulationPlatform) {
                ForEach(SimulationPlatform.allCases) { platform in
                    Text(platform.displayName).tag(platform)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            .help("Wheeled and tracked UGV presets use PX4 when required.")
        }
        .padding(.horizontal, GuardianSpacing.md)
        .padding(.vertical, GuardianSpacing.cardBodyInset)
        .background(theme.backgroundElevated)
    }

    private func vehicleCard(_ preset: SimulationVehiclePreset) -> some View {
        Button {
            if SimulationSpawnPolicy.forcesPx4ForUGV(preset: preset) {
                simulationPlatform = .px4
            }
            Task {
                if let squadID = wingmanToSquadID {
                    await roster.addWingman(to: squadID, preset: preset, sizeTier: sizeTier)
                } else {
                    await roster.addPrimaryVehicle(preset: preset, sizeTier: sizeTier)
                }
                onAdded()
            }
        } label: {
            HStack(spacing: GuardianSpacing.cardBodyInset) {
                SimulationDeviceThumbnail(imageBasenames: preset.simulationDeviceImageBasenames)
                    .frame(width: 72, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
                    Text(preset.displayName)
                        .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: GuardianSpacing.xxs) {
                        Text(preset.vehicleDomain.rawValue)
                        if SimulationSpawnPolicy.forcesPx4ForUGV(preset: preset) {
                            Text("· PX4")
                        }
                    }
                    .font(GuardianTypography.font(.inlineNoticeDetail))
                    .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(GuardianTypography.font(.inlineNoticeTitle))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(GuardianSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(GuardianPointerPlainButtonStyle())
        .disabled(controlsLocked || roster.isBusy || !fleetLink.isSimulateEnabled)
        .guardianPointerOnHover()
    }
}

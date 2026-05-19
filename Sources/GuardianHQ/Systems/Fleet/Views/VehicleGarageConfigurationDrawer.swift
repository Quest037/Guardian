import SwiftUI

/// Garage card **configure** drawer — vehicle size tier and class defaults (extensible for more fields later).
struct VehicleGarageConfigurationDrawer: View {
    let vehicleID: String
    let vehicleClass: FleetVehicleType
    let displayShortID: String
    let onTierChanged: (VehicleSizeTier) -> Void
    let onClose: () -> Void

    @ObservedObject private var sizePreferences = VehicleClassSizePreferencesStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var draftTier: VehicleSizeTier = .medium
    @State private var draftClassDefaultTier: VehicleSizeTier = .medium

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var draftFootprint: VehicleFootprint {
        VehicleClassSizeCatalogue.footprint(vehicleClass: vehicleClass, tier: draftTier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.md) {
            headerSummary

            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                Text("Size tier")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                Picker("Size tier", selection: $draftTier) {
                    ForEach(VehicleClassSizeCatalogue.tiers(for: vehicleClass), id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: draftTier) { newTier in
                    onTierChanged(newTier)
                }

                Text(draftFootprint.dimensionsLabelCm)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textTertiary)
            }

            Divider().overlay(theme.borderSubtle)

            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                Text("Default for new \(vehicleClass.displayName) vehicles")
                    .font(GuardianTypography.font(.formFieldLabel))
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Class default tier", selection: $draftClassDefaultTier) {
                    ForEach(VehicleSizeTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: draftClassDefaultTier) { newTier in
                    sizePreferences.setDefaultTier(newTier, for: vehicleClass)
                }

                Text(
                    VehicleClassSizeCatalogue.footprint(
                        vehicleClass: vehicleClass,
                        tier: draftClassDefaultTier
                    ).dimensionsLabelCm
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 0)

            GuardianThemedButton(
                title: "Done",
                accent: .primary,
                surface: .solid,
                action: onClose
            )
        }
        .padding(GuardianSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            draftTier = sizePreferences.resolvedTier(vehicleID: vehicleID, vehicleClass: vehicleClass)
            draftClassDefaultTier = sizePreferences.defaultTier(for: vehicleClass)
        }
    }

    private var headerSummary: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(displayShortID)
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            Text(vehicleClass.displayName)
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
            Text("Footprint sizes come from the vehicle size matrix (midpoint W × L × H in cm).")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

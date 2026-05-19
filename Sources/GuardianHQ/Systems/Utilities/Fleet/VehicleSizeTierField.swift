import SwiftUI

/// Shared size-tier picker + W×L×H cm hint (`VehicleClassSizeToDo.md` Phase 1).
struct VehicleSizeTierField: View {
    let vehicleClass: FleetVehicleType
    @Binding var tier: VehicleSizeTier
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var footprint: VehicleFootprint {
        VehicleClassSizeCatalogue.footprint(vehicleClass: vehicleClass, tier: tier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xxs) {
            Picker("Size tier", selection: $tier) {
                ForEach(VehicleClassSizeCatalogue.tiers(for: vehicleClass), id: \.self) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Text(footprint.dimensionsLabelCm)
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

extension FleetVehicleType {
    /// v1 operator surfaces: tier picker on mission roster for UGV-W / UGV-T first.
    var showsMissionRosterSizeTierPicker: Bool {
        self == .ugvWheeled || self == .ugvTracked
    }
}

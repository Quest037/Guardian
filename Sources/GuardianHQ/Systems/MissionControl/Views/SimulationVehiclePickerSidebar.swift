import SwiftUI

/// Slide-in panel: stack picker in the header, vehicle type cards below.
struct SimulationVehiclePickerSidebar: View {
    @Binding var platform: SimulationPlatform
    let onSelect: (SimulationVehiclePreset) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text("Select Vehicle")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Picker("Stack", selection: $platform) {
                    ForEach(SimulationPlatform.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
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

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(SimulationVehiclePreset.allCases) { preset in
                        vehicleCard(preset)
                    }
                }
                .padding(16)
            }
        }
    }

    private func vehicleCard(_ preset: SimulationVehiclePreset) -> some View {
        Button {
            onSelect(preset)
        } label: {
            HStack(spacing: 14) {
                SimulationDeviceThumbnail(imageBasenames: preset.simulationDeviceImageBasenames)
                    .frame(width: 72, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(preset.vehicleDomain.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.backgroundRaised)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

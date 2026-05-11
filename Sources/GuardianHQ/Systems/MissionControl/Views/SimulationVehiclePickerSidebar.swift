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
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text("Select Vehicle")
                    .font(GuardianTypography.font(.hudTitle16Bold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: GuardianSpacing.xs)
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

            ScrollView {
                VStack(spacing: GuardianSpacing.denseGutter) {
                    ForEach(SimulationVehiclePreset.allCases) { preset in
                        vehicleCard(preset)
                    }
                }
                .padding(GuardianSpacing.md)
            }
        }
    }

    private func vehicleCard(_ preset: SimulationVehiclePreset) -> some View {
        Button {
            onSelect(preset)
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
                    Text(preset.vehicleDomain.rawValue)
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
    }
}

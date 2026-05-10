import SwiftUI

/// Installed integrations (built-in today); enable/disable surfaces that register through ``GuardianPluginRegistry``.
struct PluginsView: View {
    @EnvironmentObject private var pluginRegistry: GuardianPluginRegistry
    @EnvironmentObject private var pluginPreferences: PluginPreferencesStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plugins")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 8)

                Text(
                    "Guardian can run built-in and third-party plugins that add features to the app. "
                        + "Each plugin does something different—turn one on or off with its switch when you want that behavior."
                )
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(pluginRegistry.manifestsOrdered()) { manifest in
                        pluginCard(manifest)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundBase)
    }

    private func pluginCard(_ manifest: GuardianPluginManifest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(manifest.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { pluginPreferences.isEnabled(manifest.pluginID) },
                        set: { enabled in
                            pluginPreferences.setEnabled(manifest.pluginID, enabled: enabled)
                            if enabled {
                                GuardianPluginRuntimeEffects.applyEnabled(manifest.pluginID)
                            } else {
                                GuardianPluginRuntimeEffects.applyDisabled(manifest.pluginID)
                            }
                        }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Off disables this plugin until you turn it on again.")
            }
            Text(manifest.pluginID.rawValue)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            Text(manifest.shortDescription)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.borderSubtle, lineWidth: 1)
        )
    }
}

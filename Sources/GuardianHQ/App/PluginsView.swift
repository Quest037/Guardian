import SwiftUI

/// Installed integrations (built-in today); enable/disable surfaces that register through ``GuardianPluginRegistry``.
struct PluginsView: View {
    @EnvironmentObject private var pluginRegistry: GuardianPluginRegistry
    @EnvironmentObject private var pluginPreferences: PluginPreferencesStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var pluginsCardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianCardLayout.defaultBodyPadding
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Plugins")
                    .font(GuardianTypography.font(.pluginsPageHero))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, GuardianSpacing.xs)

                Text(
                    "Guardian can run built-in and third-party plugins that add features to the app. "
                        + "Each plugin does something different—turn one on or off with its switch when you want that behavior."
                )
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, GuardianSpacing.lg)

                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    ForEach(pluginRegistry.manifestsOrdered()) { manifest in
                        pluginCard(manifest)
                    }
                }
            }
            .padding(GuardianSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundBase)
    }

    private func pluginCard(_ manifest: GuardianPluginManifest) -> some View {
        GuardianCard(
            configuration: pluginsCardConfiguration,
            header: {
                HStack(alignment: .center, spacing: GuardianSpacing.denseGutter) {
                    Text(manifest.displayName)
                        .font(GuardianTypography.font(.sectionHeadingSemibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle(
                        "Enabled",
                        isOn: pluginToggleBinding(for: manifest)
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help("Off disables this plugin until you turn it on again.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            },
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                    Text(manifest.pluginID.rawValue)
                        .font(GuardianTypography.font(.telemetryMono11Medium))
                        .foregroundStyle(theme.textTertiary)
                    Text(manifest.shortDescription)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private func pluginToggleBinding(for manifest: GuardianPluginManifest) -> Binding<Bool> {
        Binding(
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
    }
}

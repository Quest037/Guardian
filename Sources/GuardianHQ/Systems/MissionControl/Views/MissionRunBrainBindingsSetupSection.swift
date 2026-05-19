import SwiftUI

/// MCS **Setup → Rules** — per-run brain version overrides (seeded from pin defaults at ``MissionControlStore/createRun``).
struct MissionRunBrainBindingsSetupSection: View {
    @Binding var bindings: [MissionRunBrainBinding]
    let isEditable: Bool
    var onBindingsChanged: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var catalogueEntries: [GuardianBrainCatalogueEntry] = []
    @State private var loadError: String?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            Text("Autonomy brains on this run override pinned defaults from Settings → Brains. Bindings are keyed by training task kind and vehicle class (not each mission template task row). Pick a catalogue version before Start Run.")
                .font(GuardianTypography.font(.denseCaption12Regular))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let loadError {
                Text(loadError)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(GuardianSemanticColors.dangerForeground)
            } else if bindings.isEmpty {
                Text("No brain bindings on this run. Import packs and pin defaults in Settings → Brains.")
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textTertiary)
            } else {
                ForEach(bindings.indices, id: \.self) { index in
                    bindingRow(at: index)
                }
            }
        }
        .onAppear { reloadCatalogue() }
    }

    @ViewBuilder
    private func bindingRow(at index: Int) -> some View {
        let binding = bindings[index]
        VStack(alignment: .leading, spacing: GuardianSpacing.xsTight) {
            Text(
                "\(GuardianBrainRunUtilities.taskKindDisplayTitle(binding.taskKindRaw)) · \(GuardianBrainRunUtilities.vehicleClassDisplayTitle(binding.vehicleClassRaw))"
            )
            .font(GuardianTypography.font(.denseCaption12Medium))
            .foregroundStyle(theme.textPrimary)

            if isEditable {
                Picker(
                    "Brain version",
                    selection: Binding(
                        get: { pickerSelectionID(for: binding) },
                        set: { newID in applyPickerSelection(newID, at: index) }
                    )
                ) {
                    ForEach(matchingEntries(for: binding), id: \.id) { entry in
                        Text("\(entry.manifest.displayName) · \(entry.manifest.brainVersion.displayLabel)")
                            .tag(entry.id)
                    }
                }
                .labelsHidden()
            } else {
                Text(GuardianBrainRunUtilities.bindingCaption(binding))
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(GuardianSpacing.denseGutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(theme.backgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.borderSubtle, lineWidth: 1)
                )
        )
    }

    private func matchingEntries(for binding: MissionRunBrainBinding) -> [GuardianBrainCatalogueEntry] {
        catalogueEntries.filter {
            $0.manifest.taskKinds.contains(binding.taskKindRaw)
                && $0.manifest.vehicleClasses.contains(binding.vehicleClassRaw)
        }
    }

    private func pickerSelectionID(for binding: MissionRunBrainBinding) -> String {
        "\(binding.brainId.uuidString)-\(binding.brainVersion.semverString)"
    }

    private func applyPickerSelection(_ entryID: String, at index: Int) {
        guard let entry = catalogueEntries.first(where: { $0.id == entryID }) else { return }
        var binding = bindings[index]
        binding.brainId = entry.manifest.brainId
        binding.brainVersion = entry.manifest.brainVersion
        binding.displayName = entry.manifest.displayName
        bindings[index] = binding
        onBindingsChanged()
    }

    private func reloadCatalogue() {
        do {
            catalogueEntries = try GuardianBrainCatalogueStore.listEntries()
            loadError = nil
        } catch {
            catalogueEntries = []
            loadError = error.localizedDescription
        }
    }
}

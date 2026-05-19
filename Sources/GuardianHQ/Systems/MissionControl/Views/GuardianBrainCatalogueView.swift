import SwiftUI

/// Mission / HQ: import, pin, and manage Guardian Brain Packs (`.guardianbrain`) from Settings → Brains.
struct GuardianBrainCatalogueView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var entries: [GuardianBrainCatalogueEntry] = []
    @State private var pinnedKeys: Set<String> = []
    @State private var loadError: String?
    @State private var pendingDeleteEntry: GuardianBrainCatalogueEntry?

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.md) {
                Text("Autonomy brains")
                    .font(GuardianTypography.font(.appWindowToolbarTitle))
                    .foregroundStyle(theme.textPrimary)

                Text(
                    "Import Guardian brain versions to control how the system manages vehicles and squads in missions."
                )
                .font(GuardianTypography.font(.denseFootnoteRegular))
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: GuardianSpacing.sm) {
                    GuardianPrimaryProminentButton(title: "Import brain pack…") {
                        if GuardianBrainPackImportService.promptImportFromDisk() != nil {
                            reload()
                        }
                    }
                    GuardianThemedButton(title: "Refresh", accent: .neutral, surface: .outline) {
                        reload()
                    }
                }

                if let loadError {
                    Text(loadError)
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(GuardianSemanticColors.dangerForeground)
                }

                if entries.isEmpty {
                    Text("No imported brains yet.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textTertiary)
                } else {
                    ForEach(entries) { entry in
                        brainRow(entry)
                    }
                }
            }
            .padding(GuardianSpacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.backgroundBase)
        .onAppear { reload() }
        .guardianConfirmOverlay(item: $pendingDeleteEntry, onDismiss: { pendingDeleteEntry = nil }) { entry in
            GuardianConfirmDanger(
                title: "Delete brain pack?",
                message: "Remove \(entry.manifest.displayName) (\(entry.manifest.brainVersion.displayLabel)) from this Mac. Mission runs already created are not changed.",
                confirmTitle: "Delete",
                onCancel: { pendingDeleteEntry = nil },
                onConfirm: {
                    performDelete(entry)
                    pendingDeleteEntry = nil
                }
            )
        }
    }

    private func brainRow(_ entry: GuardianBrainCatalogueEntry) -> some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianCardLayout.defaultBodyPadding
            ),
            body: {
                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.manifest.displayName)
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(theme.textPrimary)
                        Spacer(minLength: GuardianSpacing.sm)
                        if pinnedKeys.contains(pinKey(for: entry)) {
                            Text("Pinned default")
                                .font(GuardianTypography.font(.inlineNoticeTitle))
                                .foregroundStyle(GuardianSemanticColors.successForeground)
                        }
                    }
                    Text(rowSubtitle(entry))
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                    HStack(spacing: GuardianSpacing.sm) {
                        GuardianThemedButton(title: "Pin as default", accent: .primary, surface: .outline) {
                            pinEntry(entry)
                        }
                        Button {
                            GuardianBrainPackExportService.revealInFinder(entry.packFileURL)
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                        .buttonStyle(GuardianPointerPlainButtonStyle())
                        .guardianPointerOnHover()
                        Button {
                            pendingDeleteEntry = entry
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(GuardianPointerPlainButtonStyle())
                        .guardianPointerOnHover()
                        .foregroundStyle(GuardianSemanticColors.dangerForeground)
                    }
                }
            }
        )
    }

    private func rowSubtitle(_ entry: GuardianBrainCatalogueEntry) -> String {
        let tags = [
            entry.manifest.brainVersion.displayLabel,
            entry.manifest.taskKinds.joined(separator: ", "),
            entry.manifest.vehicleClasses.joined(separator: ", "),
        ].filter { !$0.isEmpty }
        return tags.joined(separator: " · ")
    }

    private func pinKey(for entry: GuardianBrainCatalogueEntry) -> String {
        let task = entry.manifest.taskKinds.first ?? ""
        let vehicle = entry.manifest.vehicleClasses.first ?? ""
        return "\(task)|\(vehicle)|\(entry.manifest.brainId.uuidString)|\(entry.manifest.brainVersion.semverString)"
    }

    private func reload() {
        if let migration = GuardianBrainLegacySkillMigration.migrateIfNeeded(),
           migration.importedCount > 0 {
            loadError = nil
        }
        do {
            entries = try GuardianBrainCatalogueStore.listEntries()
            pinnedKeys = Set(
                try entries.compactMap { entry -> String? in
                    try GuardianBrainPinDefaultsStore.isPinned(entry: entry) ? pinKey(for: entry) : nil
                }
            )
            loadError = nil
        } catch {
            entries = []
            pinnedKeys = []
            loadError = error.localizedDescription
        }
    }

    private func pinEntry(_ entry: GuardianBrainCatalogueEntry) {
        do {
            try GuardianBrainPinDefaultsStore.pin(manifest: entry.manifest)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func performDelete(_ entry: GuardianBrainCatalogueEntry) {
        do {
            try GuardianBrainCatalogueStore.deleteEntry(entry)
            reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

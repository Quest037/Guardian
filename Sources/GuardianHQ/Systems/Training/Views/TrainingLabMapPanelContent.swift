import SwiftUI

/// Shared map catalogue (Training lab rail + drawer). No delete — authoring stays in World Builder.
struct TrainingLabMapPanelContent: View {
    @ObservedObject var training: TrainingPanelController
    let packages: [TrainingEnvironmentPackage]
    let controlsLocked: Bool
    let onSelectEnvironmentID: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toastCenter: ToastCenter
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.denseGutter) {
                Text(trainingMapPanelIntro)
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if packages.isEmpty {
                    Text("No environments installed.")
                        .font(GuardianTypography.font(.denseFootnoteRegular))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    ForEach(packages, id: \.id) { pkg in
                        TrainingLabEnvironmentChooseCard(
                            package: pkg,
                            isSelected: training.selectedEnvironmentID == pkg.id,
                            isFullyBuilt: pkg.hasConfiguredStartAndEndZones,
                            isSelectable: TrainingEnvironmentSelectionPolicy.isSelectableForTrainingLab(package: pkg),
                            controlsLocked: controlsLocked,
                            onSelect: { onSelectEnvironmentID(pkg.id) },
                            onSelectUnavailable: {
                                toastCenter.show(
                                    "This map is not fully built yet. Add start and end zones in World Builder.",
                                    style: .info,
                                    duration: 3
                                )
                            }
                        )
                    }
                }

                if let gazeboStatus = training.gazeboWorldStatusText {
                    Text(gazeboStatus)
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(GuardianSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trainingMapPanelIntro: String {
        if TrainingEnvironmentSelectionPolicy.allowsMapsWithoutStartAndEndZones {
            return "Choose a training map. The world loads in the simulator viewport when selected. Maps without start and end zones can load for now."
        }
        return "Choose a training map with start and end zones. The world loads in the simulator viewport when selected."
    }
}

// MARK: - Card (no delete)

private struct TrainingLabEnvironmentChooseCard: View {
    let package: TrainingEnvironmentPackage
    let isSelected: Bool
    let isFullyBuilt: Bool
    let isSelectable: Bool
    let controlsLocked: Bool
    let onSelect: () -> Void
    let onSelectUnavailable: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var sceneType: TrainingEnvironmentSceneType {
        TrainingEnvironmentSceneType.resolved(from: package.manifest.sceneType)
    }

    var body: some View {
        GuardianCard(
            configuration: GuardianCardConfiguration(
                border: isSelected ? .primary : .subtle,
                cornerRadius: GuardianCardLayout.cornerRadius,
                bodyPadding: GuardianSpacing.cardBodyInset
            ),
            body: {
                HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                    VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                        Text(package.manifest.displayName)
                            .font(GuardianTypography.font(.panelSecondaryHeadingSemibold))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isFullyBuilt {
                            if !package.manifest.description.isEmpty {
                                Text(package.manifest.description)
                                    .font(GuardianTypography.font(.denseFootnoteRegular))
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            Text("Not fully built yet.")
                                .font(GuardianTypography.font(.denseFootnoteRegular))
                                .foregroundStyle(GuardianSemanticColors.dangerForeground)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        HStack(spacing: GuardianSpacing.xsTight) {
                            GuardianBadge(
                                text: package.source == .bundled ? "Bundled" : "Yours",
                                accent: .neutral,
                                paint: .light,
                                size: .small,
                                shape: .pill
                            )
                            GuardianBadge(
                                text: sceneType.displayName,
                                accent: .neutral,
                                paint: .light,
                                size: .small,
                                shape: .pill
                            )
                        }
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(GuardianTypography.font(.subsectionTitleSemibold))
                            .foregroundStyle(GuardianSemanticColors.infoForeground)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
        .opacity(isSelectable ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(perform: handleTap)
        .guardianPointerOnHover()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(package.manifest.displayName)
        .accessibilityHint(isSelectable ? (isFullyBuilt ? "" : "Start and end zones not configured") : "Not fully built yet")
    }

    private func handleTap() {
        guard !controlsLocked else { return }
        guard !isSelected else { return }
        guard isSelectable else {
            onSelectUnavailable()
            return
        }
        onSelect()
    }
}

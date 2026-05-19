import SwiftUI
import UniformTypeIdentifiers

/// Training lab **Vehicles** rail / drawer — squad roster, simulator cards, drag-and-drop squads.
struct TrainingLabVehiclesPanelContent: View {
    @ObservedObject var roster: TrainingLabRosterController
    @ObservedObject var playground: FormationsPlaygroundController
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    let missionControl: MissionControlStore
    let mapReadyForVehicles: Bool
    let controlsLocked: Bool
    let onPresentAddVehicle: () -> Void
    let onPresentSquadSettings: (_ squadID: UUID, _ squadIndex: Int) -> Void
    let onOpenCalibration: (String, FleetVehicleModel?) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var retryingEntryIDs: Set<UUID> = []

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if roster.squads.isEmpty {
                emptyState
            } else {
                rosterScroll
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { roster.refreshSlotStatesFromFleet() }
    }

    private var emptyState: some View {
        VStack(spacing: GuardianSpacing.md) {
            Spacer(minLength: GuardianSpacing.lg)
            Image(systemName: "car.side")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            Text("No Vehicles")
                .font(GuardianTypography.font(.sectionHeadingSemibold))
                .foregroundStyle(theme.textPrimary)
            if mapReadyForVehicles {
                Text("Add vehicles to your training session.")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                GuardianPrimaryProminentButton(title: "Add vehicle") {
                    onPresentAddVehicle()
                }
                .disabled(controlsLocked)
            } else {
                Text("Waiting for map to load…")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: GuardianSpacing.lg)
        }
        .padding(GuardianSpacing.md)
        .frame(maxWidth: .infinity)
    }

    private var rosterScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.sectionStack) {
                if mapReadyForVehicles {
                    HStack {
                        Spacer(minLength: 0)
                        GuardianPrimaryProminentButton(title: "Add vehicle") {
                            onPresentAddVehicle()
                        }
                        .disabled(controlsLocked || roster.isBusy)
                    }
                }

                ForEach(Array(roster.squads.enumerated()), id: \.element.id) { squadIndex, squad in
                    squadSection(squadIndex: squadIndex, squad: squad)
                }

                newPrimaryDropZone
            }
            .padding(GuardianSpacing.md)
        }
    }

    private func squadSection(squadIndex: Int, squad: TrainingLabSquad) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.xs) {
                Text(TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex))
                    .font(GuardianTypography.font(.subsectionTitleSemibold))
                    .foregroundStyle(theme.textPrimary)
                if roster.isLearningSquad(squad.id) {
                    Text("Learning")
                        .font(GuardianTypography.font(.denseCaption10Semibold))
                        .foregroundStyle(GuardianSemanticColors.infoForeground)
                }
            }
            Text(squad.taskKind.displayTitle)
                .font(GuardianTypography.font(.denseCaption10Regular))
                .foregroundStyle(theme.textSecondary)

            if let slot = squad.primary.slotState {
                simulatorCard(
                    title: TrainingLabSquadCallsign.primaryLabel(squadIndex: squadIndex),
                    entry: squad.primary,
                    slot: slot,
                    squadID: squad.id,
                    isPrimary: true
                )
                .dropDestination(for: String.self) { items, _ in
                    handleSquadDrop(items: items, targetSquadID: squad.id)
                }
            }

            ForEach(Array(squad.wingmen.enumerated()), id: \.element.id) { wingIndex, wingman in
                if let slot = wingman.slotState {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: GuardianSpacing.lg)
                        simulatorCard(
                            title: TrainingLabSquadCallsign.wingmanLabel(
                                squadIndex: squadIndex,
                                wingmanIndex: wingIndex + 1
                            ),
                            entry: wingman,
                            slot: slot,
                            squadID: squad.id,
                            isPrimary: false
                        )
                        .dropDestination(for: String.self) { items, _ in
                            handleSquadDrop(items: items, targetSquadID: squad.id)
                        }
                    }
                }
            }
        }
    }

    private var newPrimaryDropZone: some View {
        RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
            .strokeBorder(theme.borderSubtle, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .overlay {
                Text("Drop wingman here to start a new primary squad")
                    .font(GuardianTypography.font(.denseFootnoteRegular))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(GuardianSpacing.sm)
            }
            .dropDestination(for: String.self) { items, _ in
                handleNewPrimaryDrop(items: items)
            }
    }

    @ViewBuilder
    private func simulatorCard(
        title: String,
        entry: TrainingLabRosterEntry,
        slot: FormationsPlaygroundSlotState,
        squadID: UUID,
        isPrimary: Bool
    ) -> some View {
        let cardLocked = controlsLocked || roster.isBusy || retryingEntryIDs.contains(entry.id)
        let showPreflightRetry = GuardianSimulatorSlotRecoveryPolicy.shouldOfferPreflightRetry(slot: slot)
        let showLinkRetry = playground.shouldOfferSimulatorRetry(slot: slot) && !showPreflightRetry

        GuardianSimulatorSlotCardView(
            title: title,
            slot: slot,
            fleetLink: fleetLink,
            sitl: sitl,
            showRetry: showLinkRetry,
            retryButtonTitle: playground.retryButtonTitle(for: slot),
            showPreflightRetry: showPreflightRetry,
            showReplace: playground.canReplaceSlot(slot),
            showSquadSettings: isPrimary,
            showDelete: true,
            cardActionsLocked: cardLocked,
            onInspect: { vehicleID, fallback in
                onOpenCalibration(vehicleID, fallback)
            },
            onSquadSettings: isPrimary
                ? { onPresentSquadSettings(squadID, roster.squadIndex(for: squadID) ?? 0) }
                : nil,
            onRetry: {
                Task {
                    retryingEntryIDs.insert(entry.id)
                    if showPreflightRetry {
                        await roster.retryPreflight(entryID: entry.id)
                    } else {
                        await roster.retryVehicle(entryID: entry.id)
                    }
                    retryingEntryIDs.remove(entry.id)
                }
            },
            onReplace: {
                Task {
                    await roster.replaceVehicle(entryID: entry.id)
                }
            },
            onDelete: {
                Task {
                    await roster.removeVehicle(entryID: entry.id)
                }
            }
        )
        .onDrag {
            let payload: TrainingLabVehicleDragPayload = isPrimary
                ? .primary(entryID: entry.id, squadID: squadID)
                : .wingman(entryID: entry.id, squadID: squadID)
            return NSItemProvider(object: payload.token as NSString)
        }
    }

    private func handleSquadDrop(items: [String], targetSquadID: UUID) -> Bool {
        guard !controlsLocked,
              let token = items.first,
              let payload = TrainingLabVehicleDragPayload.parse(token)
        else { return false }

        switch payload {
        case .primary(let entryID, let sourceSquadID):
            guard sourceSquadID != targetSquadID else { return false }
            roster.absorbPrimaryIntoSquad(draggedEntryID: entryID, targetSquadID: targetSquadID)
            return true
        case .wingman(let entryID, let sourceSquadID):
            guard sourceSquadID != targetSquadID else { return false }
            roster.moveWingmanToSquad(entryID: entryID, targetSquadID: targetSquadID)
            return true
        }
    }

    private func handleNewPrimaryDrop(items: [String]) -> Bool {
        guard !controlsLocked,
              let token = items.first,
              let payload = TrainingLabVehicleDragPayload.parse(token),
              case .wingman(let entryID, _) = payload
        else { return false }
        roster.promoteWingmanToNewSquad(entryID: entryID)
        return true
    }
}

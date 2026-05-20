import SwiftUI
import UniformTypeIdentifiers

/// Training lab **Vehicles** rail / drawer — squad roster, simulator cards, drag-and-drop squads.
struct TrainingLabVehiclesPanelContent: View {
    @ObservedObject var roster: TrainingLabRosterController
    @ObservedObject var playground: FormationsPlaygroundController
    @ObservedObject var fleetLink: FleetLinkService
    @ObservedObject var sitl: SitlService
    let missionControl: MissionControlStore
    let zones: WorldBuilderZonesSnapshot
    let mapReadyForVehicles: Bool
    let controlsLocked: Bool
    let onPresentAddVehicle: () -> Void
    let onPresentAddWingman: (_ squadID: UUID) -> Void
    let onPresentSquadSettings: (_ squadID: UUID, _ squadIndex: Int) -> Void
    let onOpenCalibration: (String, FleetVehicleModel?) -> Void
    /// Degrees to add to formation heading in one zone (e.g. ±90).
    let onRotateFormation: (
        _ squadID: UUID,
        _ phase: TrainingLabFormationSlotGeometry.ZonePhase,
        _ deltaDeg: Double
    ) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var retryingEntryIDs: Set<UUID> = []

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        Group {
            if roster.allSlotStates.isEmpty {
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
                if mapReadyForVehicles, roster.canAddAnotherSquad {
                    HStack {
                        Spacer(minLength: 0)
                        GuardianPrimaryProminentButton(title: "Add vehicle") {
                            onPresentAddVehicle()
                        }
                        .disabled(controlsLocked || roster.isBusy)
                    }
                }

                ForEach(Array(roster.squads.enumerated()), id: \.element.id) { squadIndex, squad in
                    if squad.hasLinkedSimulator {
                        squadSection(squadIndex: squadIndex, squad: squad)
                    }
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

            if mapReadyForVehicles, roster.canAddWingman(to: squad.id) {
                HStack {
                    Spacer(minLength: 0)
                    GuardianThemedButton(
                        title: "Add wingman",
                        accent: .primary,
                        surface: .outline,
                        size: .small,
                        action: { onPresentAddWingman(squad.id) }
                    )
                    .disabled(controlsLocked || roster.isBusy)
                }
            }

            if roster.mapSelectedSquadID == squad.id {
                formationRotateControls(squadID: squad.id)
            }
        }
    }

    @ViewBuilder
    private func formationRotateControls(squadID: UUID) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            if zones.start.placed {
                formationRotateRow(
                    squadID: squadID,
                    phase: .start,
                    label: "Start zone facing"
                )
            }
            if zones.end.placed {
                formationRotateRow(
                    squadID: squadID,
                    phase: .end,
                    label: "End zone facing"
                )
            }
        }
    }

    private func formationRotateRow(
        squadID: UUID,
        phase: TrainingLabFormationSlotGeometry.ZonePhase,
        label: String
    ) -> some View {
        HStack(spacing: GuardianSpacing.sm) {
            Text(label)
                .font(GuardianTypography.font(.denseCaption10Regular))
                .foregroundStyle(theme.textSecondary)
            Spacer(minLength: GuardianSpacing.xs)
            GuardianThemedButton(
                title: "Rotate left",
                accent: .primary,
                surface: .outline,
                size: .small,
                action: { onRotateFormation(squadID, phase, -90) }
            )
            .disabled(controlsLocked || roster.isBusy)
            GuardianThemedButton(
                title: "Rotate right",
                accent: .primary,
                surface: .outline,
                size: .small,
                action: { onRotateFormation(squadID, phase, 90) }
            )
            .disabled(controlsLocked || roster.isBusy)
        }
        .help("Turn this squad’s formation in the \(phase == .start ? "start" : "end") zone. Drag the gold handle on that zone’s map marker for fine control.")
    }

    @ViewBuilder
    private var newPrimaryDropZone: some View {
        if roster.canAddAnotherSquad {
            newPrimaryDropZoneContent
        }
    }

    private var newPrimaryDropZoneContent: some View {
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
        .overlay {
            if isPrimary, roster.mapSelectedSquadID == squadID {
                RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous)
                    .strokeBorder(GuardianSemanticColors.infoForeground.opacity(0.55), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: GuardianCardLayout.cornerRadius, style: .continuous))
        .onTapGesture {
            guard isPrimary else { return }
            if roster.mapSelectedSquadID == squadID {
                roster.clearMapSquadSelection()
            } else {
                roster.selectMapSquad(squadID)
            }
        }
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

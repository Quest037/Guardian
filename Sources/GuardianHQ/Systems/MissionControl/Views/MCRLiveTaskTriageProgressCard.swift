// MCRLiveTaskTriageProgressCard.swift — MC-R task triage hero progress: coordinator snapshot + primary-path ``FleetVehicleLiveChannel`` merge (Phase 6 slice).
import SwiftUI

private enum MCRLiveTaskTriageProgressCardLayout {
    static let cardConfiguration = GuardianCardConfiguration(
        border: .subtle,
        cornerRadius: GuardianCardLayout.cornerRadius,
        bodyPadding: GuardianCardLayout.defaultBodyPadding
    )
}

@MainActor
enum MCRLiveTaskTriageProgressCardPresentationResolver {
    /// Coordinator row when present; otherwise one-off ``makeRowSnapshot`` (e.g. triage opened before first apply).
    static func presentation(
        coordinator: MCRLiveTaskListSnapshotCoordinator,
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        task: RoutePath,
        taskIndex: Int,
        now: Date
    ) -> MCRLiveTaskListRowPresentation {
        if let row = coordinator.presentations.first(where: { $0.taskID == task.id }) {
            return row
        }
        let snap = MCRLiveTaskListProgressFormatting.makeRowSnapshot(
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            taskIndex: taskIndex,
            now: now
        )
        return MCRLiveTaskListRowPresentation(taskID: task.id, taskIndex: taskIndex, snapshot: snap)
    }
}

/// Task triage progress card: cycles/waypoints row, mission or per-squad bars, and shell-supplied footer chrome (deferral / trigger / stagger).
struct MCRLiveTaskTriageProgressCard<Footer: View>: View {
    @EnvironmentObject private var taskListCoordinator: MCRLiveTaskListSnapshotCoordinator
    let run: MissionRunEnvironment
    let mission: Mission
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let task: RoutePath
    let taskIndex: Int
    let now: Date
    var squadDeferralAlterRow: ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? = nil
    @ViewBuilder let footerChrome: (MCRLiveTaskListRowSnapshot, Date) -> Footer

    var body: some View {
        let base = MCRLiveTaskTriageProgressCardPresentationResolver.presentation(
            coordinator: taskListCoordinator,
            run: run,
            mission: mission,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            taskIndex: taskIndex,
            now: now
        )
        let streamID = MCRLiveTaskListProgressFormatting.resolvedPrimaryFleetStreamVehicleID(
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission
        )
        if let vid = streamID, !vid.isEmpty {
            MCRLiveTaskTriageProgressCardPrimaryHubHost(
                basePresentation: base,
                task: task,
                taskIndex: taskIndex,
                run: run,
                mission: mission,
                fleetLink: fleetLink,
                sitl: sitl,
                vehicleID: vid,
                now: now,
                squadDeferralAlterRow: squadDeferralAlterRow,
                footerChrome: footerChrome
            )
        } else {
            MCRLiveTaskTriageProgressCardBody(
                snapshot: base.snapshot,
                task: task,
                taskIndex: taskIndex,
                now: now,
                squadDeferralAlterRow: squadDeferralAlterRow,
                footerChrome: footerChrome
            )
        }
    }
}

// MARK: - Primary-path fleet hub

private struct MCRLiveTaskTriageProgressCardPrimaryHubHost<Footer: View>: View {
    let basePresentation: MCRLiveTaskListRowPresentation
    let task: RoutePath
    let taskIndex: Int
    let run: MissionRunEnvironment
    let mission: Mission
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let vehicleID: String
    let now: Date
    var squadDeferralAlterRow: ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? = nil
    @ViewBuilder let footerChrome: (MCRLiveTaskListRowSnapshot, Date) -> Footer

    @ObservedObject private var vehicleLiveChannel: FleetVehicleLiveChannel

    init(
        basePresentation: MCRLiveTaskListRowPresentation,
        task: RoutePath,
        taskIndex: Int,
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        vehicleID: String,
        now: Date,
        squadDeferralAlterRow: ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? = nil,
        @ViewBuilder footerChrome: @escaping (MCRLiveTaskListRowSnapshot, Date) -> Footer
    ) {
        self.basePresentation = basePresentation
        self.task = task
        self.taskIndex = taskIndex
        self.run = run
        self.mission = mission
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.vehicleID = vehicleID
        self.now = now
        self.squadDeferralAlterRow = squadDeferralAlterRow
        self.footerChrome = footerChrome
        _vehicleLiveChannel = ObservedObject(wrappedValue: fleetLink.mcrRosterLiveChannel(forVehicleID: vehicleID))
    }

    var body: some View {
        let merged = basePresentation.mergedWithPrimaryPathHubTelemetry(
            vehicleLiveChannel.primaryPathHubTelemetry,
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now
        )
        MCRLiveTaskTriageProgressCardBody(
            snapshot: merged.snapshot,
            task: task,
            taskIndex: taskIndex,
            now: now,
            squadDeferralAlterRow: squadDeferralAlterRow,
            footerChrome: footerChrome
        )
        .onAppear {
            fleetLink.mcrRosterRetainLiveChannel(forVehicleID: vehicleID)
            vehicleLiveChannel.refresh(from: fleetLink)
        }
        .onDisappear {
            fleetLink.mcrRosterReleaseLiveChannel(forVehicleID: vehicleID)
        }
    }
}

// MARK: - Card body

private struct MCRLiveTaskTriageProgressCardBody<Footer: View>: View {
    let snapshot: MCRLiveTaskListRowSnapshot
    let task: RoutePath
    let taskIndex: Int
    let now: Date
    var squadDeferralAlterRow: ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? = nil
    @ViewBuilder let footerChrome: (MCRLiveTaskListRowSnapshot, Date) -> Footer

    private var barTint: Color {
        if snapshot.inTaskStartDeferral, snapshot.liveTaskStartDeferral != nil {
            return Color.cyan.opacity(0.78)
        }
        return task.enabled ? MissionTaskMapColor.swiftUIColor(forTaskIndex: taskIndex) : Color.gray.opacity(0.35)
    }

    var body: some View {
        GuardianCard(configuration: MCRLiveTaskTriageProgressCardLayout.cardConfiguration, body: {
            VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                MCRLiveTaskTriageCycleWaypointCounterRow(snapshot: snapshot)
                if !snapshot.showPerSquadBars {
                    MCRLiveCapsuleProgressBar(
                        fraction: snapshot.triageCombinedBarFraction,
                        tint: barTint,
                        height: 11
                    )
                    .frame(maxWidth: .infinity)
                }

                if snapshot.showPerSquadBars {
                    MCRLiveSquadRowsFromSnapshot(
                        snapshot: snapshot,
                        compactMetrics: false,
                        deferralAlterRow: squadDeferralAlterRow
                    )
                        .padding(.top, GuardianSpacing.xxs)
                }

                footerChrome(snapshot, now)
            }
        })
    }
}

private struct MCRLiveTaskTriageCycleWaypointCounterRow: View {
    let snapshot: MCRLiveTaskListRowSnapshot

    @Environment(\.colorScheme) private var colorScheme

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    var body: some View {
        let font = GuardianTypography.font(.inlineNoticeDetail)
        HStack(alignment: .firstTextBaseline, spacing: GuardianSpacing.sm) {
            if let cycle = snapshot.cyclesLineText {
                Text(cycle)
                    .font(font)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer(minLength: GuardianSpacing.xs)
            Text(snapshot.waypointsLineText)
                .font(font)
                .foregroundStyle(theme.textSecondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Multi-primary squad tabs + wind-down (MC-R task triage)

/// Info callout for a queued after-cycle end policy; **Revoke** sits in the notice trailing slot.
struct MCRScheduledEndPolicyInlineNotice: View {
    let kind: MissionRunMissionTaskGracefulPendingKind
    let detail: String
    let onRevoke: () -> Void

    var body: some View {
        GuardianInlineNotice(
            kind: .informational,
            title: MissionControlMissionEndWindDownControlVisibility.scheduledEndPolicyNoticeTitle(for: kind),
            detail: detail,
            trailing: {
                GuardianThemedButton(
                    title: "Revoke scheduled wind-down",
                    accent: .danger,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: onRevoke
                )
                .guardianPointerOnHover()
                .help("Cancel the scheduled end-of-cycle wind-down.")
            }
        )
    }
}

/// Per-primary-squad wind-down enablement for MC-R task triage (shared tab body).
struct MCRLiveTaskTriageSquadWindDownAvailability: Equatable {
    let abortNow: Bool
    let abortGraceful: Bool
    let completeNow: Bool
    let completeGraceful: Bool
    let showAbortCard: Bool
    let showCompleteCard: Bool
    let scheduledGracefulNoticeKind: MissionRunMissionTaskGracefulPendingKind?

    var hasVisibleChrome: Bool {
        showAbortCard || showCompleteCard || scheduledGracefulNoticeKind != nil
    }

    @MainActor
    static func resolve(
        run: MissionRunEnvironment,
        task: RoutePath,
        assignment: MissionRunAssignment,
        now: Date
    ) -> MCRLiveTaskTriageSquadWindDownAvailability {
        let aid = assignment.id
        let pendingSquad = run.pendingMissionSquadGracefulWindDownKindByAssignmentID[aid]
        let taskPendingKind = run.pendingMissionTaskGracefulWindDownKindByTaskID[task.id]
        let scheduledGracefulNoticeKind = pendingSquad
        let taskPending = taskPendingKind != nil

        let hasSlots = !run.assignmentsBoundToMissionTask(taskID: task.id).isEmpty
        let runActive = run.status == .running || run.status == .paused
        let inExecutingPhase = run.sessionPhase == .executing
        let squadState = run.squadStateByAssignmentID[aid] ?? .ready
        let wholeRunGraceful = run.gracefulStopKind != .none
        let abortIssued = run.missionTaskAbortWindDownIssuedTaskIDs.contains(task.id)
        let completeIssued = run.missionTaskCompleteWindDownIssuedTaskIDs.contains(task.id)
        let squadSuppressed = run.missionSquadAutopilotAutostartSuppressedAssignmentIDs.contains(aid)

        let squadStartDef = run.squadStartDeferralByAssignmentID[aid]
        let inSquadDeferral = task.enabled && run.status == .running && (squadStartDef.map { now < $0.startAt } ?? false)

        let baseAPI = task.enabled
            && hasSlots
            && runActive
            && inExecutingPhase
            && !wholeRunGraceful
            && !taskPending

        let protocolShowsAbort = MissionControlMissionEndWindDownControlVisibility.showsAbortOptions(for: squadState)
        let protocolShowsComplete = MissionControlMissionEndWindDownControlVisibility.showsCompleteOptions(for: squadState)
        let showAbortCard = MissionControlMissionEndWindDownControlVisibility.showsSquadAbortWindDownCard(
            protocolShowsAbort: protocolShowsAbort,
            squadPending: pendingSquad,
            taskPending: taskPendingKind
        )
        let showCompleteCard = MissionControlMissionEndWindDownControlVisibility.showsSquadCompleteWindDownCard(
            protocolShowsComplete: protocolShowsComplete,
            squadPending: pendingSquad,
            taskPending: taskPendingKind
        )
        let protocolBlocksAbort = !protocolShowsAbort
        let protocolBlocksComplete = !protocolShowsComplete

        let blockedByIssued = abortIssued || completeIssued || squadSuppressed

        var abortNow = baseAPI && !protocolBlocksAbort && !blockedByIssued
        var abortGraceful = baseAPI && !protocolBlocksAbort && !blockedByIssued && !inSquadDeferral
        var completeNow = baseAPI && !protocolBlocksComplete && !blockedByIssued
        var completeGraceful = baseAPI && !protocolBlocksComplete && !blockedByIssued && !inSquadDeferral

        switch pendingSquad {
        case .some(.abortAfterCycle):
            completeNow = false
            completeGraceful = false
            abortGraceful = false
        case .some(.completeAfterCycle):
            abortNow = false
            abortGraceful = false
            completeGraceful = false
        case .none:
            break
        }

        return MCRLiveTaskTriageSquadWindDownAvailability(
            abortNow: abortNow,
            abortGraceful: abortGraceful,
            completeNow: completeNow,
            completeGraceful: completeGraceful,
            showAbortCard: showAbortCard,
            showCompleteCard: showCompleteCard,
            scheduledGracefulNoticeKind: scheduledGracefulNoticeKind
        )
    }
}

/// MC-R task triage: segmented primary-squad tabs + shared action block (end policy today; more squad actions later).
@MainActor
struct MCRLiveTaskTriageSquadActionsPanel: View {
    @ObservedObject var run: MissionRunEnvironment
    let task: RoutePath
    let mission: Mission
    let now: Date
    let onSquadAbortNow: (UUID, String) -> Void
    let onSquadAbortGraceful: (UUID, String) -> Void
    let onSquadCompleteNow: (UUID, String) -> Void
    let onSquadCompleteGraceful: (UUID, String) -> Void
    let onRunUpdated: () -> Void

    @State private var selectedAssignmentID: UUID?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var toastCenter: ToastCenter

    private var theme: GuardianThemePalette { GuardianTheme.palette(for: colorScheme) }

    private var squads: [(assignment: MissionRunAssignment, squadIndex: Int)] {
        run.primarySquads(forTaskID: task.id, mission: mission)
    }

    private var cardConfiguration: GuardianCardConfiguration {
        GuardianCardConfiguration(
            border: .subtle,
            cornerRadius: GuardianCardLayout.cornerRadius,
            bodyPadding: GuardianCardLayout.defaultBodyPadding
        )
    }

    var body: some View {
        let ordered = squads
        if ordered.count > 1 {
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                squadTabPicker(ordered: ordered)
                if let selected = resolvedSelection(in: ordered) {
                    squadActionsBlock(
                        squad: selected.squad,
                        tabLabel: selected.tabLabel,
                        confirmLabel: selected.confirmLabel,
                        availability: selected.availability
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { syncSelection(with: ordered) }
            .onChange(of: ordered.map(\.assignment.id)) { _ in syncSelection(with: ordered) }
        }
    }

    private func squadTabPicker(ordered: [(assignment: MissionRunAssignment, squadIndex: Int)]) -> some View {
        Picker("", selection: selectionBinding(ordered: ordered)) {
            ForEach(ordered, id: \.assignment.id) { squad in
                Text(primaryCallsignTabTitle(assignment: squad.assignment, squadIndex: squad.squadIndex))
                    .tag(squad.assignment.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .guardianFormControlSizing()
    }

    @ViewBuilder
    private func squadActionsBlock(
        squad: (assignment: MissionRunAssignment, squadIndex: Int),
        tabLabel: String,
        confirmLabel: String,
        availability: MCRLiveTaskTriageSquadWindDownAvailability
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
            if availability.hasVisibleChrome {
                if availability.showAbortCard {
                    windDownModeRowCard(
                        bodyCaption: "Abort",
                        accent: .danger,
                        nowEnabled: availability.abortNow,
                        nowHelpEnabled: "Issue abort-policy commands for this squad immediately.",
                        nowHelpDisabled: "Unavailable while another intent blocks it, this squad is in recovery or abort protocol, or the run is not executing.",
                        afterCycleEnabled: availability.abortGraceful,
                        afterCycleHelpEnabled: "Schedule abort-policy commands when this squad’s current mission cycle ends.",
                        afterCycleHelpDisabled: "Unavailable if another wind-down is already scheduled, during this squad’s mission start deferral, or while a whole-run graceful stop is active.",
                        onNow: { onSquadAbortNow(squad.assignment.id, confirmLabel) },
                        onAfterCycle: { onSquadAbortGraceful(squad.assignment.id, confirmLabel) }
                    )
                }
                if availability.showCompleteCard {
                    windDownModeRowCard(
                        bodyCaption: "Complete",
                        accent: .primary,
                        nowEnabled: availability.completeNow,
                        nowHelpEnabled: "Issue complete-policy recovery wind-down for this squad immediately.",
                        nowHelpDisabled: "Unavailable while another intent blocks it, this squad is in recovery or abort protocol, or the run is not executing.",
                        afterCycleEnabled: availability.completeGraceful,
                        afterCycleHelpEnabled: "Schedule recovery wind-down when this squad’s current mission cycle ends.",
                        afterCycleHelpDisabled: "Unavailable if another wind-down is already scheduled, during this squad’s mission start deferral, or while a whole-run graceful stop is active.",
                        onNow: { onSquadCompleteNow(squad.assignment.id, confirmLabel) },
                        onAfterCycle: { onSquadCompleteGraceful(squad.assignment.id, confirmLabel) }
                    )
                }
                if let scheduledKind = availability.scheduledGracefulNoticeKind {
                    MCRScheduledEndPolicyInlineNotice(
                        kind: scheduledKind,
                        detail: "",
                        onRevoke: {
                            run.revokeMissionSquadGracefulWindDown(forAssignmentID: squad.assignment.id)
                            toastCenter.show("Revoked scheduled wind-down for \(tabLabel).", style: .info)
                            onRunUpdated()
                        }
                    )
                }
            } else {
                GuardianCard(configuration: cardConfiguration, body: {
                    Text("No end-policy actions for \(tabLabel) in this state.")
                        .font(GuardianTypography.font(.denseCaption12Regular))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Matches MC-R task triage wind-down rows: caption leading, **Now** + **After cycle** trailing.
    private func windDownModeRowCard(
        bodyCaption: String,
        accent: GuardianThemeAccent,
        nowEnabled: Bool,
        nowHelpEnabled: String,
        nowHelpDisabled: String,
        afterCycleEnabled: Bool,
        afterCycleHelpEnabled: String,
        afterCycleHelpDisabled: String,
        onNow: @escaping () -> Void,
        onAfterCycle: @escaping () -> Void
    ) -> some View {
        triageActionRowCard(bodyCaption: bodyCaption) {
            HStack(spacing: GuardianSpacing.xs) {
                GuardianThemedButton(
                    title: "Now",
                    accent: accent,
                    surface: .solid,
                    size: .small,
                    shape: .cornered,
                    action: onNow
                )
                .disabled(!nowEnabled)
                .guardianPointerOnHover()
                .help(nowEnabled ? nowHelpEnabled : nowHelpDisabled)

                GuardianThemedButton(
                    title: "After cycle",
                    accent: accent,
                    surface: .outline,
                    size: .small,
                    shape: .cornered,
                    action: onAfterCycle
                )
                .disabled(!afterCycleEnabled)
                .guardianPointerOnHover()
                .help(afterCycleEnabled ? afterCycleHelpEnabled : afterCycleHelpDisabled)
            }
        }
    }

    @ViewBuilder
    private func triageActionRowCard<Trailing: View>(
        bodyCaption: String,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        GuardianCard(configuration: cardConfiguration, body: {
            HStack(alignment: .center, spacing: GuardianSpacing.sm) {
                Text(bodyCaption)
                    .font(GuardianTypography.font(.denseCaption12Regular))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
        })
    }

    private struct ResolvedSquadSelection {
        let squad: (assignment: MissionRunAssignment, squadIndex: Int)
        let tabLabel: String
        let confirmLabel: String
        let availability: MCRLiveTaskTriageSquadWindDownAvailability
    }

    private func resolvedSelection(in ordered: [(assignment: MissionRunAssignment, squadIndex: Int)]) -> ResolvedSquadSelection? {
        guard let id = selectedAssignmentID,
              let squad = ordered.first(where: { $0.assignment.id == id })
        else { return nil }
        let tabLabel = primaryCallsignTabTitle(assignment: squad.assignment, squadIndex: squad.squadIndex)
        let confirmLabel = squadConfirmLabel(assignment: squad.assignment, squadIndex: squad.squadIndex)
        let availability = MCRLiveTaskTriageSquadWindDownAvailability.resolve(
            run: run,
            task: task,
            assignment: squad.assignment,
            now: now
        )
        return ResolvedSquadSelection(
            squad: squad,
            tabLabel: tabLabel,
            confirmLabel: confirmLabel,
            availability: availability
        )
    }

    private func selectionBinding(ordered: [(assignment: MissionRunAssignment, squadIndex: Int)]) -> Binding<UUID> {
        Binding(
            get: {
                if let id = selectedAssignmentID, ordered.contains(where: { $0.assignment.id == id }) {
                    return id
                }
                return ordered.first?.assignment.id ?? UUID()
            },
            set: { selectedAssignmentID = $0 }
        )
    }

    private func syncSelection(with ordered: [(assignment: MissionRunAssignment, squadIndex: Int)]) {
        guard !ordered.isEmpty else {
            selectedAssignmentID = nil
            return
        }
        if let id = selectedAssignmentID, ordered.contains(where: { $0.assignment.id == id }) {
            return
        }
        selectedAssignmentID = ordered.first?.assignment.id
    }

    /// Segmented tab pill: primary roster callsign when set.
    private func primaryCallsignTabTitle(assignment: MissionRunAssignment, squadIndex: Int) -> String {
        let callsign = assignment.slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !callsign.isEmpty { return callsign }
        return MissionControlSquadUtilities.squadDisplayName(taskName: task.name, squadIndex: squadIndex)
    }

    /// Confirm dialogs and toasts: callsign when available, else task:squad index label.
    private func squadConfirmLabel(assignment: MissionRunAssignment, squadIndex: Int) -> String {
        let callsign = assignment.slotName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !callsign.isEmpty { return callsign }
        return MissionControlSquadUtilities.squadDisplayName(taskName: task.name, squadIndex: squadIndex)
    }
}


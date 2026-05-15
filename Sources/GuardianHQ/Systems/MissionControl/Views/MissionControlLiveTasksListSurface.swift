// MissionControlLiveTasksListSurface.swift — Phase 2 migration: MC-R **Tasks** list chrome lives outside ``MissionRunDetailView`` as its own surface. This type reads ``MCRLiveTaskListSnapshotCoordinator`` via ``@EnvironmentObject`` (injected by ``MissionControlLiveRunRoot``) plus a plain ``let run`` for the wind-down notice (no second ``@ObservedObject`` on ``MissionRunEnvironment`` here); the shell still owns ``@ObservedObject var run`` and passes it down. When a task row has a resolved primary fleet stream id, ``MissionControlLiveTasksPresentationList`` merges live hub fields from ``FleetVehicleLiveChannel`` (Phase 4 — same registry as roster).
import SwiftUI

enum MissionControlLiveTasksWindDownNotice {
    /// Surfaces active task-path or whole-run abort/complete wind-down for the Tasks card.
    @MainActor
    static func flags(for run: MissionRunEnvironment) -> (abort: Bool, complete: Bool) {
        switch run.status {
        case .running, .paused, .recovery:
            break
        default:
            return (false, false)
        }
        let runAbortGraceful = run.gracefulStopKind == .abortAfterCycle
        let runCompleteGraceful = run.gracefulStopKind == .completeAfterCycle
        let taskAbortGraceful = run.pendingMissionTaskGracefulWindDownKindByTaskID.values.contains(.abortAfterCycle)
        let taskCompleteGraceful = run.pendingMissionTaskGracefulWindDownKindByTaskID.values.contains(.completeAfterCycle)
        let squadAbortGraceful = run.pendingMissionSquadGracefulWindDownKindByAssignmentID.values.contains(.abortAfterCycle)
        let squadCompleteGraceful = run.pendingMissionSquadGracefulWindDownKindByAssignmentID.values.contains(.completeAfterCycle)
        let taskAbortIssued = !run.missionTaskAbortWindDownIssuedTaskIDs.isEmpty
        let taskCompleteIssued = !run.missionTaskCompleteWindDownIssuedTaskIDs.isEmpty
        return (
            runAbortGraceful || taskAbortGraceful || taskAbortIssued || squadAbortGraceful,
            runCompleteGraceful || taskCompleteGraceful || taskCompleteIssued || squadCompleteGraceful
        )
    }
}

struct MissionControlLiveTasksWindDownNoticeBlock: View {
    let run: MissionRunEnvironment

    var body: some View {
        let flags = MissionControlLiveTasksWindDownNotice.flags(for: run)
        if flags.abort || flags.complete {
            VStack(alignment: .leading, spacing: GuardianSpacing.xs) {
                if flags.abort {
                    GuardianInlineNotice(
                        kind: .danger,
                        title: "Abort underway",
                        detail: "Fleet wind-down for abort is dispatching or waiting on end-of-cycle steps on a task path, a primary squad, or for the whole run."
                    )
                }
                if flags.complete {
                    GuardianInlineNotice(
                        kind: .success,
                        title: "Complete underway",
                        detail: "Fleet wind-down for completion is dispatching or waiting on end-of-cycle steps on a task path, a primary squad, or for the whole run."
                    )
                }
            }
        }
    }
}

/// Scrollable task rows driven by ``MCRLiveTaskListSnapshotCoordinator``; footer chrome is composed by the shell.
struct MissionControlLiveTasksPresentationList<Footer: View>: View {
    @EnvironmentObject private var taskListCoordinator: MCRLiveTaskListSnapshotCoordinator
    let run: MissionRunEnvironment
    let mission: Mission
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let onTaskTap: (UUID) -> Void
    /// Per-primary-squad MAVLink start deferral **Sooner / Later / Start** row (task list); `nil` omits alter chrome.
    let squadDeferralAlterRow: ((RoutePath, MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)?
    @ViewBuilder let rowFooter: (RoutePath, MCRLiveTaskListRowFooterKind) -> Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                MissionControlLiveTasksWindDownNoticeBlock(run: run)
                LazyVStack(alignment: .leading, spacing: GuardianSpacing.cardBodyInset) {
                    ForEach(taskListCoordinator.presentations) { row in
                        let task = mission.routeMacro.tasks[row.taskIndex]
                        let streamID = MCRLiveTaskListProgressFormatting.resolvedPrimaryFleetStreamVehicleID(
                            run: run,
                            fleetLink: fleetLink,
                            sitl: sitl,
                            task: task,
                            mission: mission
                        )
                        GuardianCard(
                            configuration: GuardianCardConfiguration(
                                border: .subtle,
                                cornerRadius: GuardianCardLayout.cornerRadius,
                                bodyPadding: GuardianSpacing.cardBodyInset
                            ),
                            body: {
                                VStack(alignment: .leading, spacing: GuardianSpacing.sm) {
                                    MCRLiveTaskListRowPrimaryHubFleetKeyedView(
                                        presentation: row,
                                        task: task,
                                        run: run,
                                        mission: mission,
                                        fleetLink: fleetLink,
                                        sitl: sitl,
                                        primaryStreamVehicleID: streamID,
                                        squadDeferralAlterRow: squadDeferralAlterRow
                                    ) {
                                        onTaskTap(task.id)
                                    }
                                    rowFooter(task, row.snapshot.footerKind)
                                }
                            }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Primary-path fleet hub (narrow observation)

private struct MCRLiveTaskListRowPrimaryHubFleetKeyedView: View {
    let presentation: MCRLiveTaskListRowPresentation
    let task: RoutePath
    let run: MissionRunEnvironment
    let mission: Mission
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let primaryStreamVehicleID: String?
    let squadDeferralAlterRow: ((RoutePath, MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)?
    let onTap: () -> Void

    var body: some View {
        if let vid = primaryStreamVehicleID, !vid.isEmpty {
            MCRLiveTaskListRowPrimaryHubChannelHost(
                presentation: presentation,
                task: task,
                run: run,
                mission: mission,
                fleetLink: fleetLink,
                sitl: sitl,
                vehicleID: vid,
                squadDeferralAlterRow: squadDeferralAlterRow,
                onTap: onTap
            )
        } else {
            MCRLiveTaskListRowChrome(
                presentation: presentation,
                task: task,
                onTap: onTap,
                squadDeferralAlterRow: mcrLiveSquadDeferralAlterRowThreeParam(task: task, fourParam: squadDeferralAlterRow)
            )
        }
    }
}

private struct MCRLiveTaskListRowPrimaryHubChannelHost: View {
    let presentation: MCRLiveTaskListRowPresentation
    let task: RoutePath
    let run: MissionRunEnvironment
    let mission: Mission
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let vehicleID: String
    let squadDeferralAlterRow: ((RoutePath, MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)?
    let onTap: () -> Void

    @ObservedObject private var vehicleLiveChannel: FleetVehicleLiveChannel

    init(
        presentation: MCRLiveTaskListRowPresentation,
        task: RoutePath,
        run: MissionRunEnvironment,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        vehicleID: String,
        squadDeferralAlterRow: ((RoutePath, MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)?,
        onTap: @escaping () -> Void
    ) {
        self.presentation = presentation
        self.task = task
        self.run = run
        self.mission = mission
        self.fleetLink = fleetLink
        self.sitl = sitl
        self.vehicleID = vehicleID
        self.squadDeferralAlterRow = squadDeferralAlterRow
        self.onTap = onTap
        _vehicleLiveChannel = ObservedObject(wrappedValue: fleetLink.mcrRosterLiveChannel(forVehicleID: vehicleID))
    }

    var body: some View {
        let now = Date()
        let merged = presentation.mergedWithPrimaryPathHubTelemetry(
            vehicleLiveChannel.primaryPathHubTelemetry,
            run: run,
            fleetLink: fleetLink,
            sitl: sitl,
            task: task,
            mission: mission,
            now: now
        )
        MCRLiveTaskListRowChrome(
            presentation: merged,
            task: task,
            onTap: onTap,
            squadDeferralAlterRow: mcrLiveSquadDeferralAlterRowThreeParam(task: task, fourParam: squadDeferralAlterRow)
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

private func mcrLiveSquadDeferralAlterRowThreeParam(
    task: RoutePath,
    fourParam: ((RoutePath, MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)?
) -> ((MCRLiveTaskListSquadRowSnapshot, MissionTaskStartDeferral, Date) -> AnyView)? {
    fourParam.map { outer in { squad, def, now in outer(task, squad, def, now) } }
}

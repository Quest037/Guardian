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

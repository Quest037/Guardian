import Foundation

/// Wingman **convoy** follow — heading-astern assembly, then path-polyline slots after the primary reaches WP1 (`SquadFollow&Formation.md` §C).
@MainActor
final class MissionRunSquadFollowSubsystem {

    struct WingmanFollowTarget: Equatable, Sendable {
        let assignmentID: UUID
        let slotName: String
        let wingmanOrdinal: Int
        let desired: RouteCoordinate
        let convoyHeadingDeg: Double
        let usesPathPolyline: Bool
    }

    private enum SquadConvoyMode: Equatable {
        case assembling
        case following
    }

    private struct ActivePrimarySquad: Equatable {
        let primaryAssignmentID: UUID
        let taskID: UUID
        let squadIndex: Int
        let taskName: String
        var wingmanAssignmentIDs: [UUID]
        var convoyMode: SquadConvoyMode
        var assemblyStartedAt: Date?
        /// When true, tick releases the primary MAVLink mission once formation is ready.
        var launchPrimaryWhenAssembled: Bool
    }

    /// Dispatches the primary mission after convoy assembly completes.
    weak var cycleLaunchExecutor: MissionRunExecutionSubsystem?

    private struct WingmanStreamRegistration: Equatable {
        let assignmentID: UUID
        let vehicleID: String
        let primaryAssignmentID: UUID
    }

    weak var environment: MissionRunEnvironment?

    private(set) var wingmanPhaseByAssignmentID: [UUID: MissionRunSquadWingmanFollowPhase] = [:]

    func wingmanFollowPhase(forAssignmentID assignmentID: UUID) -> MissionRunSquadWingmanFollowPhase? {
        wingmanPhaseByAssignmentID[assignmentID]
    }
    private(set) var lastDesiredTargetByAssignmentID: [UUID: RouteCoordinate] = [:]

    private var activePrimaries: [UUID: ActivePrimarySquad] = [:]
    private var wingmanStreams: [UUID: WingmanStreamRegistration] = [:]
    private var tickTask: Task<Void, Never>?
    private var wingmanStreamRetryNotBefore: [UUID: Date] = [:]
    private var wingmanStreamReconnectAttempts: [UUID: Int] = [:]
    private var frozenStreamTargetByAssignmentID: [UUID: FormationFollowStream.Target] = [:]
    private var lastValidStreamTargetByAssignmentID: [UUID: FormationFollowStream.Target] = [:]
    private var betweenCyclesHoldPrimaryIDs: Set<UUID> = []
    private var cachedFleetLink: FleetLinkService?
    private var cachedSitl: SitlService?
    private var pendingPrimaryLaunchContextByAssignmentID: [UUID: MissionRunExecutionContext] = [:]
    private var convoyAssemblyReadyLoggedPrimaryIDs: Set<UUID> = []
    private var convoyPrimaryMissionLaunchedIDs: Set<UUID> = []
    /// Prevents overlapping ``startOneWingmanStream`` calls before ``wingmanStreams`` is registered.
    private var wingmanStreamStartInFlight: Set<UUID> = []
    private var offboardStreamLostLoggedAssignmentIDs: Set<UUID> = []

    private static let tickIntervalNs: UInt64 = 100_000_000
    private static var streamRetryCooldown: TimeInterval {
        MissionSquadConvoyFollowControlPolicy.streamReconnectCooldownS
    }

    func resetAllFollowState() {
        tickTask?.cancel()
        tickTask = nil
        activePrimaries = [:]
        wingmanStreams = [:]
        wingmanPhaseByAssignmentID = [:]
        lastDesiredTargetByAssignmentID = [:]
        wingmanStreamRetryNotBefore = [:]
        wingmanStreamReconnectAttempts = [:]
        frozenStreamTargetByAssignmentID = [:]
        lastValidStreamTargetByAssignmentID = [:]
        betweenCyclesHoldPrimaryIDs = []
        cachedFleetLink = nil
        cachedSitl = nil
        pendingPrimaryLaunchContextByAssignmentID = [:]
        convoyAssemblyReadyLoggedPrimaryIDs = []
        convoyPrimaryMissionLaunchedIDs = []
        wingmanStreamStartInFlight = []
        offboardStreamLostLoggedAssignmentIDs = []
    }

    private func setWingmanPhase(_ assignmentID: UUID, _ phase: MissionRunSquadWingmanFollowPhase) {
        let prior = wingmanPhaseByAssignmentID[assignmentID]
        guard prior != phase else { return }
        wingmanPhaseByAssignmentID[assignmentID] = phase
        environment?.bumpSquadFollowStatusRevision()
    }

    private func logOffboardStreamLostIfNeeded(
        wingmanAssignmentID: UUID,
        slotName: String,
        squadLog: (id: UUID, label: String)
    ) {
        guard !offboardStreamLostLoggedAssignmentIDs.contains(wingmanAssignmentID) else { return }
        offboardStreamLostLoggedAssignmentIDs.insert(wingmanAssignmentID)
        environment?.systems.logging.appendLogEvent(
            level: .warning,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowOffboardStreamLost,
            templateParams: [
                "squad": squadLog.label,
                "slot": slotName,
                "slotID": wingmanAssignmentID.uuidString,
            ]
        )
    }

    /// Clears follow bookkeeping and stops any active setpoint streams for the given assignments (wingman or primary).
    func clearFollowState(forAssignmentIDs ids: [UUID], fleetLink: FleetLinkService?) {
        guard !ids.isEmpty else { return }
        var primaryIDsToEnd: [UUID] = []
        for id in ids {
            if activePrimaries[id] != nil {
                primaryIDsToEnd.append(id)
            }
        }
        if let fleetLink {
            for primaryID in primaryIDsToEnd {
                tearDownSquadFollow(primaryAssignmentID: primaryID, fleetLink: fleetLink)
            }
        } else {
            for primaryID in primaryIDsToEnd {
                _ = activePrimaries.removeValue(forKey: primaryID)
            }
        }
        for id in ids {
            wingmanPhaseByAssignmentID.removeValue(forKey: id)
            lastDesiredTargetByAssignmentID.removeValue(forKey: id)
            lastValidStreamTargetByAssignmentID.removeValue(forKey: id)
            guard let fleetLink, let reg = wingmanStreams.removeValue(forKey: id) else { continue }
            Task {
                await fleetLink.stopFormationFollowStream(vehicleID: reg.vehicleID)
            }
        }
    }

    /// Stops wingman streams for every active primary squad on ``taskID`` (task-scoped operator wind-down).
    func onTaskWindDownStarted(taskID: UUID, fleetLink: FleetLinkService) {
        let primaryIDs = activePrimaries.values.filter { $0.taskID == taskID }.map(\.primaryAssignmentID)
        for primaryID in primaryIDs {
            tearDownSquadFollow(primaryAssignmentID: primaryID, fleetLink: fleetLink)
        }
    }

    func computeConvoyTargets(
        squad: MissionRunPlannerSubsystem.MissionTaskSquad,
        task: MissionTask,
        primaryHub: FleetHubVehicleTelemetry
    ) -> [WingmanFollowTarget]? {
        guard let lat = primaryHub.latitudeDeg, let lon = primaryHub.longitudeDeg else { return nil }
        let heading = primaryHub.headingDeg ?? primaryHub.yawDeg ?? 0
        let bindings = squad.wingmanBindings
        guard !bindings.isEmpty else { return [] }
        let spacing = MissionSquadConvoySpacingPolicy.lockedSpacing(
            taskPattern: task.pattern,
            primaryGranularClass: squad.primaryRosterDevice.vehicleClass
        )
        return bindings.enumerated().map { ordinal, binding in
            let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
                task: task,
                primaryLatitudeDeg: lat,
                primaryLongitudeDeg: lon,
                primaryHeadingDeg: heading,
                primaryMissionProgressCurrent: primaryHub.missionProgressCurrent,
                wingmanOrdinal: ordinal,
                spacing: spacing
            )
            return WingmanFollowTarget(
                assignmentID: binding.assignment.id,
                slotName: binding.assignment.slotName,
                wingmanOrdinal: ordinal,
                desired: slot.coordinate,
                convoyHeadingDeg: slot.convoyHeadingDeg,
                usesPathPolyline: slot.usesPathPolyline
            )
        }
    }

    /// Builds or resumes heading-based convoy formation; holds the primary until assembled when ``launchPrimaryWhenReady`` is true.
    func preparePrimaryCycleLaunch(
        mission: Mission,
        task: MissionTask,
        plannedSquad: MissionRunPlannerSubsystem.PlannedTaskSquadMission,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        launchContext: MissionRunExecutionContext?,
        launchPrimaryWhenReady: Bool
    ) {
        cachedFleetLink = fleetLink
        cachedSitl = sitl
        let squad = plannedSquad.squad
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: task.id,
            taskName: task.name,
            squadIndex: plannedSquad.squadIndex
        )
        guard let environment else {
            logFollowSkipped(squadLog: squadLog, reason: "run_environment_unavailable")
            return
        }
        guard !squad.wingmanBindings.isEmpty else { return }
        guard let primaryToken = squad.primaryAssignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: primaryToken),
              let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
              let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID),
              let targets = computeConvoyTargets(squad: squad, task: task, primaryHub: primaryHub)
        else {
            logFollowSkipped(squadLog: squadLog, reason: "primary_unavailable_for_convoy_assembly")
            return
        }
        logConvoyTargetsComputed(squadLog: squadLog, targets: targets)
        guard !targets.isEmpty else { return }

        let primaryID = squad.primaryAssignment.id
        clearBetweenCyclesHold(primaryAssignmentID: primaryID)
        let wingmanIDs = targets.map(\.assignmentID)
        for target in targets {
            setWingmanPhase(target.assignmentID, .assemblingConvoy)
            lastDesiredTargetByAssignmentID[target.assignmentID] = target.desired
        }

        if launchPrimaryWhenReady {
            environment.markMissionSquadConvoyAssemblyHold(forAssignmentID: primaryID)
            if let launchContext {
                pendingPrimaryLaunchContextByAssignmentID[primaryID] = launchContext
            }
            convoyPrimaryMissionLaunchedIDs.remove(primaryID)
        }

        let now = Date()
        var active = activePrimaries[primaryID] ?? ActivePrimarySquad(
            primaryAssignmentID: primaryID,
            taskID: task.id,
            squadIndex: plannedSquad.squadIndex,
            taskName: task.name,
            wingmanAssignmentIDs: wingmanIDs,
            convoyMode: .assembling,
            assemblyStartedAt: now,
            launchPrimaryWhenAssembled: launchPrimaryWhenReady
        )
        active.convoyMode = .assembling
        active.assemblyStartedAt = active.assemblyStartedAt ?? now
        active.launchPrimaryWhenAssembled = launchPrimaryWhenReady
        activePrimaries[primaryID] = active

        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowConvoyAssemblyStarted,
            templateParams: [
                "squad": squadLog.label,
                "wingmanCount": String(targets.count),
            ]
        )

        ensureTickLoop(fleetLink: fleetLink, sitl: sitl)
        Task {
            await startWingmanStreamsSequential(
                targets: targets,
                task: task,
                primaryHub: primaryHub,
                primaryVehicleClass: squad.primaryRosterDevice.vehicleClass,
                primaryAssignmentID: primaryID,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
            tryEvaluateConvoyAssembly(primaryAssignmentID: primaryID, fleetLink: fleetLink, sitl: sitl)
        }
    }

    /// Re-forms convoy astern of the primary (pause, between-cycle gap, post-cycle hold).
    func beginConvoyRebuild(
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        launchPrimaryWhenReady: Bool
    ) {
        cachedFleetLink = fleetLink
        cachedSitl = sitl
        guard let environment, let mission = environment.template,
              var active = activePrimaries[primaryAssignmentID],
              let assignment = environment.assignments.first(where: { $0.id == primaryAssignmentID }),
              let task = mission.routeMacro.tasks.first(where: { $0.id == active.taskID })
        else { return }

        active.convoyMode = .assembling
        active.assemblyStartedAt = Date()
        active.launchPrimaryWhenAssembled = launchPrimaryWhenReady
        activePrimaries[primaryAssignmentID] = active

        if launchPrimaryWhenReady {
            environment.markMissionSquadConvoyAssemblyHold(forAssignmentID: primaryAssignmentID)
        }

        for wingmanID in active.wingmanAssignmentIDs {
            if wingmanStreams[wingmanID] != nil {
                setWingmanPhase(wingmanID, .assemblingConvoy)
            }
        }

        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: active.squadIndex
        )
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowConvoyRebuildStarted,
            templateParams: ["squad": squadLog.label]
        )

        ensureTickLoop(fleetLink: fleetLink, sitl: sitl)
        Task {
            guard let primaryToken = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: primaryToken),
                  let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
                  let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID)
            else { return }
            let primaryVehicleClass = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })?
                .vehicleClass
            let targets: [WingmanFollowTarget]
            if let planned = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: active.taskID)
                .first(where: { $0.squad.primaryAssignment.id == primaryAssignmentID }),
               let squadTargets = computeConvoyTargets(squad: planned.squad, task: task, primaryHub: primaryHub) {
                targets = squadTargets
            } else if let bindingTargets = computeConvoyTargetsFromBindings(
                wingmanAssignmentIDs: active.wingmanAssignmentIDs,
                task: task,
                primaryHub: primaryHub,
                primaryRosterDevice: assignment.rosterDeviceId,
                mission: mission,
                environment: environment
            ) {
                targets = bindingTargets
            } else {
                return
            }
            await startWingmanStreamsSequential(
                targets: targets,
                task: task,
                primaryHub: primaryHub,
                primaryVehicleClass: primaryVehicleClass,
                primaryAssignmentID: primaryAssignmentID,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
            tryEvaluateConvoyAssembly(primaryAssignmentID: primaryAssignmentID, fleetLink: fleetLink, sitl: sitl)
        }
    }

    /// After operator **Continue mission** from squad park — re-check formation, then launch primary when ready.
    func resumeConvoyAssemblyForPrimaryLaunch(
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard var active = activePrimaries[primaryAssignmentID] else { return }
        active.launchPrimaryWhenAssembled = true
        active.convoyMode = .assembling
        active.assemblyStartedAt = Date()
        activePrimaries[primaryAssignmentID] = active
        environment?.markMissionSquadConvoyAssemblyHold(forAssignmentID: primaryAssignmentID)
        convoyPrimaryMissionLaunchedIDs.remove(primaryAssignmentID)
        if let ctx = environment?.effectiveExecutionContextForDispatch() {
            pendingPrimaryLaunchContextByAssignmentID[primaryAssignmentID] = ctx
        }
        ensureTickLoop(fleetLink: fleetLink, sitl: sitl)
        tryEvaluateConvoyAssembly(
            primaryAssignmentID: primaryAssignmentID,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    func onPrimaryMissionUnderway(primaryAssignmentID: UUID) {
        guard var active = activePrimaries[primaryAssignmentID] else { return }
        active.convoyMode = .following
        active.launchPrimaryWhenAssembled = false
        activePrimaries[primaryAssignmentID] = active
        for wingmanID in active.wingmanAssignmentIDs {
            if wingmanStreams[wingmanID] != nil {
                setWingmanPhase(wingmanID, .following)
            }
        }
    }

    func onPrimarySquadMissionDispatched(
        mission: Mission,
        task: MissionTask,
        plannedSquad: MissionRunPlannerSubsystem.PlannedTaskSquadMission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        let squad = plannedSquad.squad
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: task.id,
            taskName: task.name,
            squadIndex: plannedSquad.squadIndex
        )
        guard environment != nil else {
            logFollowSkipped(squadLog: squadLog, reason: "run_environment_unavailable")
            return
        }
        if squad.wingmanBindings.isEmpty {
            logFollowSkipped(squadLog: squadLog, reason: "no_wingmen_bound")
            return
        }
        guard let primaryToken = squad.primaryAssignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: primaryToken),
              let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
        else {
            logFollowSkipped(squadLog: squadLog, reason: "primary_vehicle_unresolved")
            return
        }
        guard let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID) else {
            logFollowSkipped(squadLog: squadLog, reason: "primary_hub_unavailable")
            return
        }
        guard let targets = computeConvoyTargets(squad: squad, task: task, primaryHub: primaryHub) else {
            logFollowSkipped(squadLog: squadLog, reason: "primary_position_unknown")
            return
        }
        for target in targets {
            setWingmanPhase(target.assignmentID, .targetsComputed)
            lastDesiredTargetByAssignmentID[target.assignmentID] = target.desired
        }
        logConvoyTargetsComputed(squadLog: squadLog, targets: targets)

        preparePrimaryCycleLaunch(
            mission: mission,
            task: task,
            plannedSquad: plannedSquad,
            fleetLink: fleetLink,
            sitl: sitl,
            launchContext: nil,
            launchPrimaryWhenReady: false
        )
    }

    func onPrimarySquadCycleEnded(
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment, let mission = environment.template,
              let active = activePrimaries[primaryAssignmentID],
              let task = mission.routeMacro.tasks.first(where: { $0.id == active.taskID })
        else {
            beginConvoyRebuild(
                primaryAssignmentID: primaryAssignmentID,
                fleetLink: fleetLink,
                sitl: sitl,
                launchPrimaryWhenReady: false
            )
            return
        }
        applyBetweenCyclesPolicy(
            primaryAssignmentID: primaryAssignmentID,
            action: task.betweenCycles,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    /// Applies the task between-cycles tactic to wingmen (hold pose, or stop streams before park/RTL dispatch).
    func applyBetweenCyclesPolicy(
        primaryAssignmentID: UUID,
        action: MissionTaskBetweenCyclesAction,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let active = activePrimaries[primaryAssignmentID] else { return }
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: active.squadIndex
        )
        switch action {
        case .holdPosition:
            beginBetweenCyclesHold(
                primaryAssignmentID: primaryAssignmentID,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
        case .returnToLaunch, .park:
            betweenCyclesHoldPrimaryIDs.remove(primaryAssignmentID)
            frozenStreamTargetByAssignmentID = frozenStreamTargetByAssignmentID.filter {
                !active.wingmanAssignmentIDs.contains($0.key)
            }
            for wingmanID in active.wingmanAssignmentIDs {
                wingmanStreamReconnectAttempts.removeValue(forKey: wingmanID)
                guard let reg = wingmanStreams.removeValue(forKey: wingmanID) else {
                    setWingmanPhase(wingmanID, .idle)
                    continue
                }
                Task {
                    await fleetLink.stopFormationFollowStream(vehicleID: reg.vehicleID)
                    setWingmanPhase(wingmanID, .idle)
                }
            }
            environment?.systems.logging.appendLogEvent(
                level: .info,
                taskID: squadLog.id,
                taskLabel: squadLog.label,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.squadFollowBetweenCyclesWingmenReleased,
                templateParams: [
                    "squad": squadLog.label,
                    "tactic": action.displayTitle,
                ]
            )
        }
    }

    private func beginBetweenCyclesHold(
        primaryAssignmentID: UUID,
        squadLog: (id: UUID, label: String),
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard var active = activePrimaries[primaryAssignmentID] else { return }
        betweenCyclesHoldPrimaryIDs.insert(primaryAssignmentID)
        active.convoyMode = .following
        activePrimaries[primaryAssignmentID] = active
        for wingmanID in active.wingmanAssignmentIDs {
            setWingmanPhase(wingmanID, .holdingBetweenCycles)
            if let reg = wingmanStreams[wingmanID],
               let hub = fleetLink.hubTelemetry(forVehicleID: reg.vehicleID),
               let lat = hub.latitudeDeg, let lon = hub.longitudeDeg {
                let coord = lastDesiredTargetByAssignmentID[wingmanID]
                    ?? RouteCoordinate(lat: lat, lon: lon)
                let yaw = hub.headingDeg ?? hub.yawDeg ?? 0
                let absAlt = hub.absoluteAltM ?? hub.altitudeAmslM ?? 0
                frozenStreamTargetByAssignmentID[wingmanID] = FormationFollowStream.Target(
                    coord: coord,
                    absoluteAltitudeM: absAlt,
                    yawDeg: yaw,
                    pursuitForwardMS: nil,
                    pursuitYawspeedDegS: nil
                )
            }
        }
        ensureTickLoop(fleetLink: fleetLink, sitl: sitl)
        environment?.systems.logging.appendLogEvent(
            level: .info,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowBetweenCyclesHold,
            templateParams: ["squad": squadLog.label]
        )
    }

    func clearBetweenCyclesHold(primaryAssignmentID: UUID) {
        betweenCyclesHoldPrimaryIDs.remove(primaryAssignmentID)
        guard let active = activePrimaries[primaryAssignmentID] else { return }
        for wingmanID in active.wingmanAssignmentIDs {
            frozenStreamTargetByAssignmentID.removeValue(forKey: wingmanID)
            if wingmanPhaseByAssignmentID[wingmanID] == .holdingBetweenCycles {
                setWingmanPhase(wingmanID, .idle)
            }
        }
    }

    func resetReconnectAttempts(forPrimaryAssignmentID primaryAssignmentID: UUID) {
        guard let active = activePrimaries[primaryAssignmentID] else { return }
        for wingmanID in active.wingmanAssignmentIDs {
            wingmanStreamReconnectAttempts.removeValue(forKey: wingmanID)
            wingmanStreamRetryNotBefore.removeValue(forKey: wingmanID)
        }
    }

    /// Operator chose **Retry formation** after stream exhaustion.
    func retryFormationFollowAfterOperatorAck(
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        resetReconnectAttempts(forPrimaryAssignmentID: primaryAssignmentID)
        guard let environment, let mission = environment.template,
              let active = activePrimaries[primaryAssignmentID],
              let assignment = environment.assignments.first(where: { $0.id == primaryAssignmentID }),
              let task = mission.routeMacro.tasks.first(where: { $0.id == active.taskID }),
              let primaryToken = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: primaryToken),
              let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
              let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID),
              let targets = computeConvoyTargetsFromBindings(
                wingmanAssignmentIDs: active.wingmanAssignmentIDs,
                task: task,
                primaryHub: primaryHub,
                primaryRosterDevice: assignment.rosterDeviceId,
                mission: mission,
                environment: environment
              )
        else { return }
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: active.squadIndex
        )
        ensureTickLoop(fleetLink: fleetLink, sitl: sitl)
        Task {
            await startWingmanStreamsSequential(
                targets: targets,
                task: task,
                primaryHub: primaryHub,
                primaryVehicleClass: mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })?.vehicleClass,
                primaryAssignmentID: primaryAssignmentID,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
        }
    }

    /// Operator chose **Park squad** after stream exhaustion.
    func parkSquadAfterFormationFollowAbort(
        primaryAssignmentID: UUID,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment,
              let taskID = environment.resolvedTaskID(forSquadAssignmentID: primaryAssignmentID, mission: mission)
        else {
            tearDownSquadFollow(primaryAssignmentID: primaryAssignmentID, fleetLink: fleetLink)
            return
        }
        let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: taskID)
        guard let squad = squads.first(where: { $0.squad.primaryAssignment.id == primaryAssignmentID }) else {
            tearDownSquadFollow(primaryAssignmentID: primaryAssignmentID, fleetLink: fleetLink)
            return
        }
        var assignmentIDs = [primaryAssignmentID]
        assignmentIDs.append(contentsOf: squad.squad.wingmanBindings.map(\.assignment.id))
        clearFollowState(forAssignmentIDs: assignmentIDs, fleetLink: fleetLink)
        for row in [squad.squad.primaryAssignment] + squad.squad.wingmanBindings.map(\.assignment) {
            guard let tokenKey = row.attachedFleetVehicleToken, !tokenKey.isEmpty else { continue }
            let issued = MissionRunIssuedCommand(
                assignmentID: row.id,
                slotName: row.slotName,
                vehicleTokenKey: tokenKey,
                dispatch: .catalogue(name: .fleetVehicleDoPark, parameters: .empty),
                issuer: .operator,
                issuerKey: "operator.squad_follow.park_squad",
                category: .missionControl
            )
            environment.appendEvent(
                environment.systems.commands.dispatchCommand(issued, fleetLink: fleetLink, sitl: sitl)
            )
        }
    }

    private func recordWingmanStreamReconnectFailure(
        wingmanAssignmentID: UUID,
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        let attempts = (wingmanStreamReconnectAttempts[wingmanAssignmentID] ?? 0) + 1
        wingmanStreamReconnectAttempts[wingmanAssignmentID] = attempts
        setWingmanPhase(wingmanAssignmentID, .streamFailed)
        guard attempts >= MissionSquadConvoyFollowControlPolicy.streamReconnectMaxAttempts else { return }
        guard let environment else { return }
        guard !environment.isMissionSquadFormationFollowHalted(forAssignmentID: primaryAssignmentID) else { return }
        let active = activePrimaries[primaryAssignmentID]
        let failedIDs = (active?.wingmanAssignmentIDs ?? []).filter {
            (wingmanStreamReconnectAttempts[$0] ?? 0) >= MissionSquadConvoyFollowControlPolicy.streamReconnectMaxAttempts
        }
        let ids = failedIDs.isEmpty ? [wingmanAssignmentID] : failedIDs
        environment.reportFormationFollowStreamExhausted(
            primaryAssignmentID: primaryAssignmentID,
            failedWingmanAssignmentIDs: ids,
            fleetLink: fleetLink,
            sitl: sitl
        )
    }

    /// Operator wind-down / run teardown — stop streams and drop squad follow state (no rebuild).
    func tearDownSquadFollow(primaryAssignmentID: UUID, fleetLink: FleetLinkService) {
        guard let active = activePrimaries.removeValue(forKey: primaryAssignmentID) else { return }
        environment?.clearMissionSquadConvoyAssemblyHold(forAssignmentID: primaryAssignmentID)
        pendingPrimaryLaunchContextByAssignmentID.removeValue(forKey: primaryAssignmentID)
        convoyAssemblyReadyLoggedPrimaryIDs.remove(primaryAssignmentID)
        convoyPrimaryMissionLaunchedIDs.remove(primaryAssignmentID)
        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: active.squadIndex
        )
        for wingmanID in active.wingmanAssignmentIDs {
            guard let reg = wingmanStreams.removeValue(forKey: wingmanID) else { continue }
            Task {
                await fleetLink.stopFormationFollowStream(vehicleID: reg.vehicleID)
                setWingmanPhase(wingmanID, .idle)
                environment?.systems.logging.appendLogEvent(
                    level: .info,
                    taskID: squadLog.id,
                    taskLabel: squadLog.label,
                    speaker: .missionControl,
                    templateKey: MissionRunLogTemplateKey.squadFollowStreamStopped,
                    templateParams: [
                        "squad": squadLog.label,
                        "slotID": wingmanID.uuidString,
                    ]
                )
            }
        }
        if activePrimaries.isEmpty {
            tickTask?.cancel()
            tickTask = nil
        }
    }

    func stopAllFollowStreams(fleetLink: FleetLinkService) async {
        tickTask?.cancel()
        tickTask = nil
        let regs = wingmanStreams
        wingmanStreams = [:]
        activePrimaries = [:]
        for (_, reg) in regs {
            await fleetLink.stopFormationFollowStream(vehicleID: reg.vehicleID)
            setWingmanPhase(reg.assignmentID, .idle)
        }
    }

    // MARK: - Promotion, release, reserve swap-in

    /// RoE **SquadPromote**: wingman stops follow, takes mission authority; remaining wingmen retarget its telemetry.
    func promoteWingmanToSquadPrimary(
        formerPrimaryAssignmentID: UUID,
        promotedWingmanAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService,
        launchPrimaryWhenReady: Bool = false
    ) {
        guard let active = activePrimaries.removeValue(forKey: formerPrimaryAssignmentID) else { return }
        environment?.clearMissionSquadConvoyAssemblyHold(forAssignmentID: formerPrimaryAssignmentID)
        pendingPrimaryLaunchContextByAssignmentID.removeValue(forKey: formerPrimaryAssignmentID)
        convoyAssemblyReadyLoggedPrimaryIDs.remove(formerPrimaryAssignmentID)
        convoyPrimaryMissionLaunchedIDs.remove(formerPrimaryAssignmentID)

        var wingmanIDs = active.wingmanAssignmentIDs.filter { $0 != promotedWingmanAssignmentID }
        if !wingmanIDs.contains(formerPrimaryAssignmentID),
           environment?.assignments.first(where: { $0.id == formerPrimaryAssignmentID })?
            .attachedFleetVehicleToken != nil {
            wingmanIDs.append(formerPrimaryAssignmentID)
        }

        if let reg = wingmanStreams.removeValue(forKey: promotedWingmanAssignmentID) {
            Task { await fleetLink.stopFormationFollowStream(vehicleID: reg.vehicleID) }
        }
        setWingmanPhase(promotedWingmanAssignmentID, .idle)
        lastValidStreamTargetByAssignmentID.removeValue(forKey: promotedWingmanAssignmentID)

        activePrimaries[promotedWingmanAssignmentID] = ActivePrimarySquad(
            primaryAssignmentID: promotedWingmanAssignmentID,
            taskID: active.taskID,
            squadIndex: active.squadIndex,
            taskName: active.taskName,
            wingmanAssignmentIDs: wingmanIDs,
            convoyMode: .following,
            assemblyStartedAt: nil,
            launchPrimaryWhenAssembled: launchPrimaryWhenReady
        )

        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: active.squadIndex
        )
        environment?.systems.logging.appendLogEvent(
            level: .info,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowWingmanPromotedToPrimary,
            templateParams: [
                "squad": squadLog.label,
                "promotedSlotID": promotedWingmanAssignmentID.uuidString,
                "formerPrimarySlotID": formerPrimaryAssignmentID.uuidString,
            ]
        )

        beginConvoyRebuild(
            primaryAssignmentID: promotedWingmanAssignmentID,
            fleetLink: fleetLink,
            sitl: sitl,
            launchPrimaryWhenReady: launchPrimaryWhenReady
        )
    }

    /// RoE **RosterRelease**: remove a wingman from the active follow loop (stream stopped; slot may void separately).
    func releaseWingmanFromSquadFollow(
        wingmanAssignmentID: UUID,
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService
    ) {
        guard var active = activePrimaries[primaryAssignmentID] else { return }
        active.wingmanAssignmentIDs.removeAll { $0 == wingmanAssignmentID }
        activePrimaries[primaryAssignmentID] = active
        if let reg = wingmanStreams.removeValue(forKey: wingmanAssignmentID) {
            Task {
                await fleetLink.stopFormationFollowStream(vehicleID: reg.vehicleID)
                setWingmanPhase(wingmanAssignmentID, .idle)
            }
        } else {
            setWingmanPhase(wingmanAssignmentID, .idle)
        }
        lastValidStreamTargetByAssignmentID.removeValue(forKey: wingmanAssignmentID)
        frozenStreamTargetByAssignmentID.removeValue(forKey: wingmanAssignmentID)
        wingmanStreamReconnectAttempts.removeValue(forKey: wingmanAssignmentID)
    }

    /// After reserve swap-in on a wingman vacancy while its leader squad is still in follow mode.
    func resumeWingmanFollowAfterReserveSwapIfNeeded(
        vacancyAssignmentID: UUID,
        mission: Mission,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment,
              let assignment = environment.assignments.first(where: { $0.id == vacancyAssignmentID })
        else { return }
        let taskID: UUID? = {
            if let tid = assignment.taskId { return tid }
            let enabled = mission.routeMacro.tasks.filter(\.enabled)
            if enabled.count == 1 { return enabled.first?.id }
            return nil
        }()
        guard let taskID else { return }

        let squads = environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: taskID)
        guard let planned = squads.first(where: {
            $0.squad.wingmanBindings.contains(where: { $0.assignment.id == vacancyAssignmentID })
        }),
              activePrimaries[planned.squad.primaryAssignment.id] != nil
        else { return }

        let primaryAssignment = planned.squad.primaryAssignment
        guard let active = activePrimaries[primaryAssignment.id],
              let task = mission.routeMacro.tasks.first(where: { $0.id == active.taskID }),
              let primaryToken = primaryAssignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: primaryToken),
              let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
              let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID),
              let targets = computeConvoyTargetsFromBindings(
                wingmanAssignmentIDs: active.wingmanAssignmentIDs,
                task: task,
                primaryHub: primaryHub,
                primaryRosterDevice: primaryAssignment.rosterDeviceId,
                mission: mission,
                environment: environment
              ),
              let target = targets.first(where: { $0.assignmentID == vacancyAssignmentID })
        else { return }

        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: planned.squadIndex
        )
        let primaryDevice = planned.squad.primaryRosterDevice
        ensureTickLoop(fleetLink: fleetLink, sitl: sitl)
        Task {
            await startOneWingmanStream(
                target: target,
                primaryHub: primaryHub,
                primaryVehicleClass: primaryDevice.vehicleClass,
                primaryAssignmentID: primaryAssignment.id,
                primaryAbsAlt: primaryHub.absoluteAltM ?? primaryHub.altitudeAmslM ?? 0,
                primarySpeedMS: primaryHub.horizontalGroundSpeedMS,
                convoyHeadingDeg: target.convoyHeadingDeg,
                yawDeg: target.convoyHeadingDeg,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
        }
    }

    // MARK: - Private

    private func effectiveGeofencesForPrimary(
        active: ActivePrimarySquad,
        mission: Mission,
        environment: MissionRunEnvironment
    ) -> [MissionGeofence] {
        environment.systems.planner.buildTaskSquadMissions(mission: mission, taskId: active.taskID)
            .first(where: { $0.squad.primaryAssignment.id == active.primaryAssignmentID })?
            .effectiveGeofencesForSquad ?? []
    }

    private func streamFormationTargetToWingman(
        reg: WingmanStreamRegistration,
        wingmanAssignmentID: UUID,
        proposed: FormationFollowStream.Target,
        geofences: [MissionGeofence],
        fleetLink: FleetLinkService
    ) {
        guard !fleetLink.shouldDeferFormationFollowSetpoints(vehicleID: reg.vehicleID) else { return }
        if !MissionControlSquadConvoySetpointGeofenceUtilities.setpointViolatesGeofences(
            coordinate: proposed.coord,
            geofences: geofences
        ) {
            lastValidStreamTargetByAssignmentID[wingmanAssignmentID] = proposed
        }
        let streamed = MissionControlSquadConvoySetpointGeofenceUtilities.filteredFormationTarget(
            proposed: proposed,
            lastValid: lastValidStreamTargetByAssignmentID[wingmanAssignmentID],
            geofences: geofences
        )
        fleetLink.updateFormationFollowTarget(vehicleID: reg.vehicleID, target: streamed)
    }

    private func ensureTickLoop(fleetLink: FleetLinkService, sitl: SitlService) {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickIntervalNs)
                guard let self, !Task.isCancelled else { return }
                self.tick(fleetLink: fleetLink, sitl: sitl)
            }
        }
    }

    private func tick(fleetLink: FleetLinkService, sitl: SitlService) {
        cachedFleetLink = fleetLink
        cachedSitl = sitl
        guard let environment, let mission = environment.template else { return }
        for active in activePrimaries.values {
            if environment.isMissionSquadFormationFollowHalted(forAssignmentID: active.primaryAssignmentID) {
                continue
            }
            if betweenCyclesHoldPrimaryIDs.contains(active.primaryAssignmentID) {
                for wingmanID in active.wingmanAssignmentIDs {
                    guard let reg = wingmanStreams[wingmanID],
                          let frozen = frozenStreamTargetByAssignmentID[wingmanID]
                    else { continue }
                    if !fleetLink.shouldDeferFormationFollowSetpoints(vehicleID: reg.vehicleID) {
                        fleetLink.updateFormationFollowTarget(vehicleID: reg.vehicleID, target: frozen)
                    }
                    setWingmanPhase(wingmanID, .holdingBetweenCycles)
                }
                continue
            }
            let squadGeofences = effectiveGeofencesForPrimary(
                active: active,
                mission: mission,
                environment: environment
            )
            guard let assignment = environment.assignments.first(where: { $0.id == active.primaryAssignmentID }),
                  let primaryToken = assignment.attachedFleetVehicleToken,
                  let token = FleetMissionVehicleToken(storageKey: primaryToken),
                  let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
                  let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID),
                  let task = mission.routeMacro.tasks.first(where: { $0.id == active.taskID }),
                  let targets = computeConvoyTargetsFromBindings(
                    wingmanAssignmentIDs: active.wingmanAssignmentIDs,
                    task: task,
                    primaryHub: primaryHub,
                    primaryRosterDevice: assignment.rosterDeviceId,
                    mission: mission,
                    environment: environment
                  )
            else { continue }

            let primaryAbsAlt = primaryHub.absoluteAltM ?? primaryHub.altitudeAmslM ?? 0
            let squadLog = MissionControlSquadUtilities.squadLogContext(
                taskID: active.taskID,
                taskName: active.taskName,
                squadIndex: active.squadIndex
            )
            let primaryDevice = mission.rosterDevices.first(where: { $0.id == assignment.rosterDeviceId })
            let primarySpeed = primaryHub.horizontalGroundSpeedMS
            for target in targets {
                lastDesiredTargetByAssignmentID[target.assignmentID] = target.desired
                if let reg = wingmanStreams[target.assignmentID] {
                    if !fleetLink.isFormationFollowStreaming(vehicleID: reg.vehicleID) {
                        wingmanStreams.removeValue(forKey: target.assignmentID)
                        logOffboardStreamLostIfNeeded(
                            wingmanAssignmentID: target.assignmentID,
                            slotName: target.slotName,
                            squadLog: squadLog
                        )
                        setWingmanPhase(target.assignmentID, .streamFailed)
                        retryStartWingmanStreamIfNeeded(
                            target: target,
                            primaryAssignmentID: active.primaryAssignmentID,
                            primaryHub: primaryHub,
                            primaryVehicleClass: primaryDevice?.vehicleClass,
                            primaryAbsAlt: primaryAbsAlt,
                            primarySpeedMS: primarySpeed,
                            convoyHeadingDeg: target.convoyHeadingDeg,
                            yawDeg: target.convoyHeadingDeg,
                            squadLog: squadLog,
                            fleetLink: fleetLink,
                            sitl: sitl
                        )
                    } else {
                        let wingmanAbsAlt = fleetLink.hubTelemetry(forVehicleID: reg.vehicleID)?.absoluteAltM
                            ?? fleetLink.hubTelemetry(forVehicleID: reg.vehicleID)?.altitudeAmslM
                            ?? primaryAbsAlt
                        let proposed = formationStreamTarget(
                            slot: target.desired,
                            yawDeg: target.convoyHeadingDeg,
                            convoyHeadingDeg: target.convoyHeadingDeg,
                            primarySpeedMS: primarySpeed,
                            wingmanVehicleID: reg.vehicleID,
                            wingmanAbsAlt: wingmanAbsAlt,
                            usesPathPolyline: target.usesPathPolyline,
                            fleetLink: fleetLink
                        )
                        streamFormationTargetToWingman(
                            reg: reg,
                            wingmanAssignmentID: target.assignmentID,
                            proposed: proposed,
                            geofences: squadGeofences,
                            fleetLink: fleetLink
                        )
                        let followPhase: MissionRunSquadWingmanFollowPhase =
                            active.convoyMode == .assembling ? .assemblingConvoy : .following
                        setWingmanPhase(target.assignmentID, followPhase)
                    }
                } else {
                    retryStartWingmanStreamIfNeeded(
                        target: target,
                        primaryAssignmentID: active.primaryAssignmentID,
                        primaryHub: primaryHub,
                        primaryVehicleClass: primaryDevice?.vehicleClass,
                        primaryAbsAlt: primaryAbsAlt,
                        primarySpeedMS: primarySpeed,
                        convoyHeadingDeg: target.convoyHeadingDeg,
                        yawDeg: target.convoyHeadingDeg,
                        squadLog: squadLog,
                        fleetLink: fleetLink,
                        sitl: sitl
                    )
                }
            }
            if active.convoyMode == .assembling {
                tryEvaluateConvoyAssembly(
                    primaryAssignmentID: active.primaryAssignmentID,
                    fleetLink: fleetLink,
                    sitl: sitl
                )
            }
        }
    }

    private func tryEvaluateConvoyAssembly(
        primaryAssignmentID: UUID,
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        guard let environment,
              let mission = environment.template,
              let active = activePrimaries[primaryAssignmentID],
              active.convoyMode == .assembling,
              let assignment = environment.assignments.first(where: { $0.id == primaryAssignmentID }),
              let task = mission.routeMacro.tasks.first(where: { $0.id == active.taskID }),
              let primaryToken = assignment.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: primaryToken),
              let primaryVehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl),
              let primaryHub = fleetLink.hubTelemetry(forVehicleID: primaryVehicleID),
              let targets = computeConvoyTargetsFromBindings(
                wingmanAssignmentIDs: active.wingmanAssignmentIDs,
                task: task,
                primaryHub: primaryHub,
                primaryRosterDevice: assignment.rosterDeviceId,
                mission: mission,
                environment: environment
              )
        else { return }

        var positions: [UUID: (lat: Double, lon: Double)] = [:]
        for target in targets {
            guard let reg = wingmanStreams[target.assignmentID],
                  let hub = fleetLink.hubTelemetry(forVehicleID: reg.vehicleID),
                  let lat = hub.latitudeDeg,
                  let lon = hub.longitudeDeg
            else { return }
            positions[target.assignmentID] = (lat, lon)
        }

        let timedOut: Bool = {
            guard let started = active.assemblyStartedAt else { return false }
            return Date().timeIntervalSince(started) >= MissionSquadConvoyFollowControlPolicy.convoyAssemblyTimeoutS
        }()

        let assembled = MissionRunSquadConvoyAssemblyUtilities.isConvoyAssembled(
            targets: targets.map { ($0.assignmentID, $0.desired) },
            wingmanPositionByAssignmentID: positions
        )

        guard assembled || timedOut else { return }

        let squadLog = MissionControlSquadUtilities.squadLogContext(
            taskID: active.taskID,
            taskName: active.taskName,
            squadIndex: active.squadIndex
        )
        if !convoyAssemblyReadyLoggedPrimaryIDs.contains(primaryAssignmentID) {
            convoyAssemblyReadyLoggedPrimaryIDs.insert(primaryAssignmentID)
            environment.systems.logging.appendLogEvent(
                level: timedOut ? .warning : .info,
                taskID: squadLog.id,
                taskLabel: squadLog.label,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.squadFollowConvoyAssemblyReady,
                templateParams: [
                    "squad": squadLog.label,
                    "timedOut": timedOut ? "true" : "false",
                ]
            )
        }

        guard active.launchPrimaryWhenAssembled,
              !convoyPrimaryMissionLaunchedIDs.contains(primaryAssignmentID)
        else { return }

        let ctx = pendingPrimaryLaunchContextByAssignmentID[primaryAssignmentID]
            ?? environment.effectiveExecutionContextForDispatch()
        guard let ctx else { return }

        convoyPrimaryMissionLaunchedIDs.insert(primaryAssignmentID)
        pendingPrimaryLaunchContextByAssignmentID.removeValue(forKey: primaryAssignmentID)
        cycleLaunchExecutor?.launchPrimaryMissionAfterConvoyAssembly(
            taskID: active.taskID,
            primaryAssignmentID: primaryAssignmentID,
            context: ctx
        )
        onPrimaryMissionUnderway(primaryAssignmentID: primaryAssignmentID)
    }

    private func formationStreamTarget(
        slot: RouteCoordinate,
        yawDeg: Double,
        convoyHeadingDeg: Double,
        primarySpeedMS: Double?,
        wingmanVehicleID: String,
        wingmanAbsAlt: Double,
        usesPathPolyline: Bool,
        fleetLink: FleetLinkService
    ) -> FormationFollowStream.Target {
        let hub = fleetLink.hubTelemetry(forVehicleID: wingmanVehicleID)
        let wLat = hub?.latitudeDeg
        let wLon = hub?.longitudeDeg
        let alongErrorM: Double?
        let lateralM: Double
        let distToSlot: Double
        if let wLat, let wLon {
            alongErrorM = MissionControlSquadConvoyFormationUtilities.convoyAlongTrackErrorM(
                wingmanLatitudeDeg: wLat,
                wingmanLongitudeDeg: wLon,
                slotCoordinate: slot,
                convoyHeadingDeg: convoyHeadingDeg
            )
            lateralM = MissionControlSquadConvoyFormationUtilities.convoyLateralErrorM(
                wingmanLatitudeDeg: wLat,
                wingmanLongitudeDeg: wLon,
                slotCoordinate: slot,
                convoyHeadingDeg: convoyHeadingDeg
            )
            distToSlot = MissionTelemetryGeo.horizontalDistanceM(
                lat1: wLat, lon1: wLon, lat2: slot.lat, lon2: slot.lon
            )
        } else {
            alongErrorM = nil
            lateralM = 0
            distToSlot = 0
        }

        let directBeyondM = usesPathPolyline
            ? MissionSquadConvoyFollowControlPolicy.pathAnchoredDirectSlotBeyondM
            : MissionSquadConvoyFollowControlPolicy.directSlotBeyondM
        let coord: RouteCoordinate
        if let wLat, let wLon {
            coord = MissionControlSquadConvoyFormationUtilities.streamedConvoySetpointCoordinate(
                wingmanLatitudeDeg: wLat,
                wingmanLongitudeDeg: wLon,
                slotCoordinate: slot,
                convoyHeadingDeg: convoyHeadingDeg,
                alongErrorM: alongErrorM,
                directSlotBeyondM: directBeyondM
            )
        } else {
            coord = slot
        }

        let pursuitForward: Float?
        let pursuitYaw: Float?
        if let alongErrorM {
            let speed = MissionControlSquadConvoyFormationUtilities.pursuitForwardSpeedMS(
                alongErrorM: alongErrorM,
                distToSlotM: distToSlot,
                primarySpeedMS: primarySpeedMS
            )
            pursuitForward = Float(speed)
            pursuitYaw = Float(
                MissionControlSquadConvoyFormationUtilities.pursuitYawRateDegS(
                    wingmanHeadingDeg: hub?.headingDeg ?? hub?.yawDeg,
                    convoyHeadingDeg: convoyHeadingDeg,
                    lateralErrorM: lateralM
                )
            )
        } else {
            pursuitForward = nil
            pursuitYaw = nil
        }

        return FormationFollowStream.Target(
            coord: coord,
            absoluteAltitudeM: wingmanAbsAlt,
            yawDeg: yawDeg,
            pursuitForwardMS: pursuitForward,
            pursuitYawspeedDegS: pursuitYaw
        )
    }

    /// Tick-path convoy targets from cached wingman assignment ids (avoids replanning squads at 10 Hz).
    private func computeConvoyTargetsFromBindings(
        wingmanAssignmentIDs: [UUID],
        task: MissionTask,
        primaryHub: FleetHubVehicleTelemetry,
        primaryRosterDevice: UUID,
        mission: Mission,
        environment: MissionRunEnvironment
    ) -> [WingmanFollowTarget]? {
        guard let lat = primaryHub.latitudeDeg, let lon = primaryHub.longitudeDeg else { return nil }
        let heading = primaryHub.headingDeg ?? primaryHub.yawDeg ?? 0
        let rosterByID = Dictionary(uniqueKeysWithValues: mission.rosterDevices.map { ($0.id, $0) })
        let primaryDevice = rosterByID[primaryRosterDevice]
        let wingmanClass: FleetVehicleType? = {
            for assignmentID in wingmanAssignmentIDs {
                guard let row = environment.assignments.first(where: { $0.id == assignmentID }),
                      let device = rosterByID[row.rosterDeviceId]
                else { continue }
                return device.vehicleClass
            }
            return nil
        }()
        let spacing = MissionSquadConvoySpacingPolicy.lockedSpacing(
            taskPattern: task.pattern,
            primaryGranularClass: primaryDevice?.vehicleClass ?? wingmanClass
        )
        var ordinal = 0
        var out: [WingmanFollowTarget] = []
        out.reserveCapacity(wingmanAssignmentIDs.count)
        for assignmentID in wingmanAssignmentIDs {
            guard let row = environment.assignments.first(where: { $0.id == assignmentID }) else { continue }
            let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
                task: task,
                primaryLatitudeDeg: lat,
                primaryLongitudeDeg: lon,
                primaryHeadingDeg: heading,
                primaryMissionProgressCurrent: primaryHub.missionProgressCurrent,
                wingmanOrdinal: ordinal,
                spacing: spacing
            )
            out.append(
                WingmanFollowTarget(
                    assignmentID: assignmentID,
                    slotName: row.slotName,
                    wingmanOrdinal: ordinal,
                    desired: slot.coordinate,
                    convoyHeadingDeg: slot.convoyHeadingDeg,
                    usesPathPolyline: slot.usesPathPolyline
                )
            )
            ordinal += 1
        }
        return out
    }

    private func startWingmanStreamsSequential(
        targets: [WingmanFollowTarget],
        task: MissionTask,
        primaryHub: FleetHubVehicleTelemetry,
        primaryVehicleClass: FleetVehicleType?,
        primaryAssignmentID: UUID,
        squadLog: (id: UUID, label: String),
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async {
        let primaryAbsAlt = primaryHub.absoluteAltM ?? primaryHub.altitudeAmslM ?? 0
        let primarySpeed = primaryHub.horizontalGroundSpeedMS
        for target in targets {
            await startOneWingmanStream(
                target: target,
                primaryHub: primaryHub,
                primaryVehicleClass: primaryVehicleClass,
                primaryAssignmentID: primaryAssignmentID,
                primaryAbsAlt: primaryAbsAlt,
                primarySpeedMS: primarySpeed,
                convoyHeadingDeg: target.convoyHeadingDeg,
                yawDeg: target.convoyHeadingDeg,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
        }
    }

    private func retryStartWingmanStreamIfNeeded(
        target: WingmanFollowTarget,
        primaryAssignmentID: UUID,
        primaryHub: FleetHubVehicleTelemetry,
        primaryVehicleClass: FleetVehicleType?,
        primaryAbsAlt: Double,
        primarySpeedMS: Double?,
        convoyHeadingDeg: Double,
        yawDeg: Double,
        squadLog: (id: UUID, label: String),
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) {
        let phase = wingmanPhaseByAssignmentID[target.assignmentID]
        guard phase == .targetsComputed || phase == .assemblingConvoy || phase == .streamFailed else { return }
        let now = Date()
        if let notBefore = wingmanStreamRetryNotBefore[target.assignmentID], now < notBefore {
            return
        }
        wingmanStreamRetryNotBefore[target.assignmentID] = now.addingTimeInterval(Self.streamRetryCooldown)
        Task {
            await startOneWingmanStream(
                target: target,
                primaryHub: primaryHub,
                primaryVehicleClass: primaryVehicleClass,
                primaryAssignmentID: primaryAssignmentID,
                primaryAbsAlt: primaryAbsAlt,
                primarySpeedMS: primarySpeedMS,
                convoyHeadingDeg: convoyHeadingDeg,
                yawDeg: yawDeg,
                squadLog: squadLog,
                fleetLink: fleetLink,
                sitl: sitl
            )
        }
    }

    private func startOneWingmanStream(
        target: WingmanFollowTarget,
        primaryHub: FleetHubVehicleTelemetry,
        primaryVehicleClass: FleetVehicleType?,
        primaryAssignmentID: UUID,
        primaryAbsAlt: Double,
        primarySpeedMS: Double?,
        convoyHeadingDeg: Double,
        yawDeg: Double,
        squadLog: (id: UUID, label: String),
        fleetLink: FleetLinkService,
        sitl: SitlService
    ) async {
        if wingmanStreamStartInFlight.contains(target.assignmentID) {
            return
        }
        if let reg = wingmanStreams[target.assignmentID] {
            if fleetLink.isFormationFollowStreaming(vehicleID: reg.vehicleID) {
                let mode = activePrimaries[primaryAssignmentID]?.convoyMode
                let followPhase: MissionRunSquadWingmanFollowPhase =
                    mode == .assembling ? .assemblingConvoy : .following
                setWingmanPhase(target.assignmentID, followPhase)
                return
            }
            wingmanStreams.removeValue(forKey: target.assignmentID)
        }
        wingmanStreamStartInFlight.insert(target.assignmentID)
        defer { wingmanStreamStartInFlight.remove(target.assignmentID) }
        guard let binding = environment?.assignments.first(where: { $0.id == target.assignmentID }),
              let tokenKey = binding.attachedFleetVehicleToken,
              let token = FleetMissionVehicleToken(storageKey: tokenKey),
              let vehicleID = resolvedFleetStreamVehicleID(token: token, fleetLink: fleetLink, sitl: sitl)
        else {
            setWingmanPhase(target.assignmentID, .streamFailed)
            return
        }

        let wingmanAbsAlt = fleetLink.hubTelemetry(forVehicleID: vehicleID)?.absoluteAltM
            ?? fleetLink.hubTelemetry(forVehicleID: vehicleID)?.altitudeAmslM
            ?? primaryAbsAlt
        let streamTarget = formationStreamTarget(
            slot: target.desired,
            yawDeg: target.convoyHeadingDeg,
            convoyHeadingDeg: target.convoyHeadingDeg,
            primarySpeedMS: primarySpeedMS,
            wingmanVehicleID: vehicleID,
            wingmanAbsAlt: wingmanAbsAlt,
            usesPathPolyline: target.usesPathPolyline,
            fleetLink: fleetLink
        )
        let started = await fleetLink.startFormationFollowStream(
            vehicleID: vehicleID,
            initialTarget: streamTarget
        )
        if started {
            offboardStreamLostLoggedAssignmentIDs.remove(target.assignmentID)
            wingmanStreamReconnectAttempts.removeValue(forKey: target.assignmentID)
            wingmanStreams[target.assignmentID] = WingmanStreamRegistration(
                assignmentID: target.assignmentID,
                vehicleID: vehicleID,
                primaryAssignmentID: primaryAssignmentID
            )
            let mode = activePrimaries[primaryAssignmentID]?.convoyMode
            let followPhase: MissionRunSquadWingmanFollowPhase =
                mode == .assembling ? .assemblingConvoy : .following
            setWingmanPhase(target.assignmentID, followPhase)
            environment?.systems.logging.appendLogEvent(
                level: .info,
                taskID: squadLog.id,
                taskLabel: squadLog.label,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.squadFollowStreamStarted,
                templateParams: [
                    "squad": squadLog.label,
                    "slot": target.slotName,
                    "slotID": target.assignmentID.uuidString,
                ]
            )
        } else {
            recordWingmanStreamReconnectFailure(
                wingmanAssignmentID: target.assignmentID,
                primaryAssignmentID: primaryAssignmentID,
                fleetLink: fleetLink,
                sitl: sitl
            )
            environment?.systems.logging.appendLogEvent(
                level: .warning,
                taskID: squadLog.id,
                taskLabel: squadLog.label,
                speaker: .missionControl,
                templateKey: MissionRunLogTemplateKey.squadFollowStreamFailed,
                templateParams: [
                    "squad": squadLog.label,
                    "slot": target.slotName,
                    "slotID": target.assignmentID.uuidString,
                    "attempt": String(wingmanStreamReconnectAttempts[target.assignmentID] ?? 0),
                ]
            )
        }
    }

    private func logFollowSkipped(squadLog: (id: UUID, label: String), reason: String) {
        guard let environment else { return }
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowSkipped,
            templateParams: [
                "squad": squadLog.label,
                "reason": reason,
            ]
        )
    }

    private func logConvoyTargetsComputed(
        squadLog: (id: UUID, label: String),
        targets: [WingmanFollowTarget]
    ) {
        guard let environment, !targets.isEmpty else { return }
        let summary = targets.map { t in
            "\(t.slotName)=\(String(format: "%.5f", t.desired.lat)),\(String(format: "%.5f", t.desired.lon))"
        }.joined(separator: "; ")
        environment.systems.logging.appendLogEvent(
            level: .info,
            taskID: squadLog.id,
            taskLabel: squadLog.label,
            speaker: .missionControl,
            templateKey: MissionRunLogTemplateKey.squadFollowConvoyTargetsComputed,
            templateParams: [
                "squad": squadLog.label,
                "wingmanCount": String(targets.count),
                "targets": summary,
            ]
        )
    }
}

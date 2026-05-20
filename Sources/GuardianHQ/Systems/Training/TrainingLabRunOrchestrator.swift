import Combine
import Foundation

/// Training lab **transit run** — all linked single-vehicle squads start zone → end zone (Phase 4c).
@MainActor
final class TrainingLabRunOrchestrator: ObservableObject {
    @Published private(set) var phase: TrainingRunPhase = .idle
    @Published private(set) var result: TrainingRunResult = .idle
    @Published private(set) var statusText: String = ""
    @Published private(set) var logLines: [TrainingPanelLogLine] = []
    /// Nav2 / geodesic polylines for the Gazebo viewport (cleared when a new run starts).
    @Published private(set) var transitRouteOverlays: [TrainingLabTransitRouteOverlayPath] = []

    private static let monitorIntervalNs: UInt64 = 1_000_000_000
    /// Whole-run wall clock cap. Phase 4d waypoints: consider pausing or excluding authorized
    /// per-waypoint **delay/dwell** from this budget (same policy as stuck — see Phase 4d checklist).
    private static let runTimeoutS: TimeInterval = 300

    private weak var lab: TrainingLabController?
    private weak var boundRoster: TrainingLabRosterController?
    private var monitorTask: Task<Void, Never>?
    private var transitDriveTask: Task<Void, Never>?
    private var proxySyncTask: Task<Void, Never>?
    private var activePlans: [TrainingLabRunVehiclePlan] = []
    private var squadDriveFailed: Set<UUID> = []
    private var learningSquadID: UUID?
    private var runStartedAt: Date?
    private var mapGeodeticOriginForRun: SimSpawnDefaults?
    private var mapHalfExtentMForRun: Double = 500
    private var safetyProgressTracks: [String: TrainingLabRunSafetyMonitor.VehicleProgressTrack] = [:]
    /// Resolved drive polylines (Nav2 or geodesic) for along-path stuck detection.
    private var transitPathsByVehicleID: [String: [RouteCoordinate]] = [:]
    private var pathSourceByVehicleID: [String: TrainingNav2PlanPathResponse.Source] = [:]
    private var resolvedPathsByVehicleID: [String: TrainingLabTransitMotion.PathResolution] = [:]

    var isSessionActive: Bool {
        phase == .staged || phase == .running
    }

    /// Whether ``completeRun(terminalPhase:...)`` may tear down the session (must use **current** phase, not the terminal outcome).
    static func sessionAllowsCompletion(whileIn sessionPhase: TrainingRunPhase) -> Bool {
        sessionPhase == .running || sessionPhase == .staged
    }

    func bind(lab: TrainingLabController) {
        self.lab = lab
    }

    func start(
        roster: TrainingLabRosterController,
        zones: WorldBuilderZonesSnapshot,
        mapHalfExtentM: Double
    ) async {
        guard let lab,
              let fleetLink = lab.teaching.fleetLinkForMapSession,
              let environment = lab.teaching.selectedEnvironment
        else {
            failRun(message: "Training run could not access fleet or map.", code: .executionFailed)
            return
        }

        stopMonitor()
        phase = .idle
        result = .idle
        logLines = []
        activePlans = []
        squadDriveFailed = []
        learningSquadID = nil
        mapGeodeticOriginForRun = nil
        mapHalfExtentMForRun = mapHalfExtentM
        safetyProgressTracks = [:]
        transitPathsByVehicleID = [:]
        pathSourceByVehicleID = [:]
        resolvedPathsByVehicleID = [:]
        transitRouteOverlays = []
        lab.onTransitRouteOverlaysDidChange?()
        boundRoster = roster

        roster.ensureZoneFormationAnchors(zones: zones)
        let staging = TrainingLabFormationSlotStaging.validate(
            squads: roster.squads,
            zones: zones,
            mapHalfExtentM: mapHalfExtentM
        )
        guard staging.isReady else {
            let message = TrainingRunOutcomeFormatting.operatorMessage(from: staging.issues)
            result = TrainingRunResult(
                phase: .failed,
                squadOutcomes: [],
                startedAt: nil,
                finishedAt: Date()
            )
            phase = .failed
            statusText = message
            appendLog("Run blocked: \(message)")
            return
        }

        let spawnDefaults = lab.teaching.spawnDefaultsForMapSession
        let mapGeodeticOrigin = TrainingLabMapSessionLifecycle.mapGeodeticOrigin(
            environment: environment,
            spawnDefaults: spawnDefaults
        )
        let planBuild = TrainingLabRunGoalResolution.buildSessionPlan(
            squads: roster.squads,
            zones: zones,
            environment: environment,
            mapGeodeticOrigin: mapGeodeticOrigin,
            learningSquadID: roster.learningSquadID
        )
        guard let sessionPlan = planBuild.plans else {
            let message = planBuild.issues.map(\.message).joined(separator: " ")
            result = TrainingRunResult(
                phase: .failed,
                squadOutcomes: [],
                startedAt: nil,
                finishedAt: Date()
            )
            phase = .failed
            statusText = message
            appendLog("Run blocked: \(message)")
            return
        }

        activePlans = sessionPlan.vehiclePlans
        mapGeodeticOriginForRun = mapGeodeticOrigin
        learningSquadID = roster.learningSquadID
            ?? activePlans.first(where: { $0.role == .learning })?.squadID
        phase = .staged
        statusText = "Staging transit run…"
        appendLog("Transit run staged — \(activePlans.count) squad(s).")
        for plan in activePlans {
            let role = plan.role == .learning ? "Learning" : "Supporting"
            let endMode = plan.requiresStrictEndSlotBox ? "end slot box" : "centre arrival"
            appendLog(
                "\(plan.squadLabel) (\(role)): \(plan.vehicleID) start→end layout resolved (\(endMode))."
            )
        }
        appendLog("Map geodetic origin: lat=\(String(format: "%.5f", mapGeodeticOrigin.latitudeDeg)), lon=\(String(format: "%.5f", mapGeodeticOrigin.longitudeDeg)).")

        await lab.buildMap(roster: roster, runLog: mapRunLogHandler())
        roster.syncTrainingFromLearningSquad()

        if let learning = roster.learningSquad,
           let learningPlan = activePlans.first(where: { $0.squadID == learning.id }) {
            lab.teaching.setTransitRunLayout(learningPlan.layout)
            lab.teaching.vehicleClass = learning.primary.vehicleClass
            lab.teaching.vehicleSizeTier = learning.primary.vehicleSizeTier
        }

        runStartedAt = Date()
        result = TrainingRunResult(
            phase: .running,
            squadOutcomes: [],
            startedAt: runStartedAt,
            finishedAt: nil
        )
        phase = .running
        statusText = "Transit run in progress…"
        appendLog("Map built. Planning routes for transit (Nav2 or geodesic fallback).")
        appendLog(TrainingLabRunPathPlanning.nav2StackLogLine(fleetLink: fleetLink))

        let runPaths = await TrainingLabRunPathPlanning.resolveAllForRun(
            fleetLink: fleetLink,
            plans: activePlans
        )
        resolvedPathsByVehicleID = runPaths.byVehicleID
        if let origin = mapGeodeticOriginForRun {
            transitRouteOverlays = TrainingLabTransitRouteOverlay.makePaths(
                plans: activePlans,
                resolvedByVehicleID: runPaths.byVehicleID,
                mapGeodeticOrigin: origin
            )
            lab.onTransitRouteOverlaysDidChange?()
            let overlayPts = transitRouteOverlays.reduce(0) { $0 + $1.pointCount }
            appendLog("Route overlay: \(transitRouteOverlays.count) path(s), \(overlayPts) map point(s) sent to 3D view.")
        }
        for plan in activePlans {
            guard let path = runPaths.byVehicleID[plan.vehicleID] else { continue }
            transitPathsByVehicleID[plan.vehicleID] = path.points
            pathSourceByVehicleID[plan.vehicleID] = path.source
            appendLog(TrainingLabRunPathPlanning.routeLogLine(plan: plan, path: path))
        }

        if let learning = roster.learningSquad,
           let learningPlan = activePlans.first(where: { $0.squadID == learning.id }),
           let path = runPaths.byVehicleID[learningPlan.vehicleID] {
            lab.teaching.applyRunPlannedPath(points: path.points, source: path.source)
        }

        appendLog("Driving squads to end zones (open-loop path follow).")
        appendLog(
            "Safety: map bounds enforced; stuck if no along-route progress for \(Int(TrainingLabRunSafetyMonitor.stuckNoProgressWindowS)) s (after \(Int(TrainingLabRunSafetyMonitor.stuckGraceAfterStartS)) s grace)."
        )

        GuardianApplicationLifecycle.shared.beginBackgroundLabRun()
        startMonitor(fleetLink: fleetLink, spawnDefaults: lab.teaching.spawnDefaultsForMapSession)
        startGazeboProxyTelemetrySync(fleetLink: fleetLink, gazebo: lab.teaching.gazeboForMapSession)
        startTransitDrive(fleetLink: fleetLink)
        appendLog("Gazebo proxies follow live hub telemetry during the run (~5 Hz).")
    }

    func stop(roster: TrainingLabRosterController) async {
        lab?.teaching.cancelTeaching()
        if let lab {
            await lab.stopActiveFormationSession()
        }
        if phase == .running || phase == .staged {
            appendLog("Stop requested.")
            let aborted = activePlans.map { plan in
                TrainingRunSquadOutcome.failed(
                    squadID: plan.squadID,
                    code: .aborted,
                    message: "Run stopped by operator."
                )
            }
            await completeRun(terminalPhase: .failed, squadOutcomes: aborted, status: "Run stopped.")
        } else {
            phase = .idle
            result = .idle
            statusText = ""
            activePlans = []
            squadDriveFailed = []
            learningSquadID = nil
            runStartedAt = nil
            mapGeodeticOriginForRun = nil
            safetyProgressTracks = [:]
            transitPathsByVehicleID = [:]
            pathSourceByVehicleID = [:]
            resolvedPathsByVehicleID = [:]
            boundRoster = nil
            GuardianApplicationLifecycle.shared.endBackgroundLabRun()
        }
        // Keep ``transitRouteOverlays`` until the next run starts (debug compare vs zone seams).
    }

    // MARK: - Transit drive (detached — fleet hops on ``FleetLinkService`` main actor)

    private func startTransitDrive(fleetLink: FleetLinkService) {
        transitDriveTask?.cancel()
        let plans = activePlans
        let preResolved = resolvedPathsByVehicleID
        transitDriveTask = Task.detached(priority: .userInitiated) { [weak self] in
            await TrainingLabTransitMotion.runParallelSquadDrives(
                fleetLink: fleetLink,
                plans: plans,
                preResolvedByVehicleID: preResolved,
                deliverReport: { report in
                    await MainActor.run {
                        self?.ingestTransitDriveReport(report)
                    }
                },
                finishWithFailures: {
                    await MainActor.run {
                        self?.finishTransitDriveAfterFailuresIfNeeded()
                    }
                }
            )
        }
    }

    private func startGazeboProxyTelemetrySync(
        fleetLink: FleetLinkService,
        gazebo: GazeboService?
    ) {
        guard let gazebo else { return }
        let vehicleIDs = activePlans.map(\.vehicleID)
        guard let origin = mapGeodeticOriginForRun else { return }
        proxySyncTask?.cancel()
        proxySyncTask = Task { @MainActor [weak self] in
            await TrainingLabGazeboProxyTelemetrySync.runWhileActive(
                gazebo: gazebo,
                fleetLink: fleetLink,
                vehicleIDs: vehicleIDs,
                mapGeodeticOrigin: origin,
                shouldContinue: { [weak self] in
                    self?.phase == .running
                }
            )
        }
    }

    private func stopGazeboProxyTelemetrySync() {
        proxySyncTask?.cancel()
        proxySyncTask = nil
    }

    private func stopTransitDrive(fleetLink: FleetLinkService?) {
        transitDriveTask?.cancel()
        transitDriveTask = nil
        guard let fleetLink else { return }
        let plans = activePlans
        guard !plans.isEmpty else { return }
        Task { @MainActor [fleetLink, plans] in
            for plan in plans {
                await fleetLink.stopTrainingControlStream(vehicleID: plan.vehicleID)
            }
        }
    }

    /// Called from detached squad-drive tasks on the main actor.
    func ingestTransitDriveReport(_ report: TrainingLabTransitMotion.SquadDriveReport) {
        for line in report.logLines {
            appendLog("[Drive] \(line)")
        }
        if let failureMessage = report.failureMessage {
            squadDriveFailed.insert(report.squadID)
            appendLog("[Drive] \(failureMessage)")
        }
    }

    /// Ends the run when any squad drive errors and the operator prefers fail-fast.
    func finishTransitDriveAfterFailuresIfNeeded() {
        guard phase == .running, !squadDriveFailed.isEmpty else { return }
        guard TrainingLabRunPreferences.failRunOnFirstSquadFailure else { return }
        let outcomes = activePlans.map { plan in
            if squadDriveFailed.contains(plan.squadID) {
                return TrainingRunSquadOutcome.failed(
                    squadID: plan.squadID,
                    code: .executionFailed,
                    message: "\(plan.squadLabel): drive to end zone failed."
                )
            }
            return TrainingRunSquadOutcome.failed(
                squadID: plan.squadID,
                code: .aborted,
                message: "\(plan.squadLabel): run ended because another squad failed."
            )
        }
        Task { await completeRun(
            terminalPhase: .failed,
            squadOutcomes: outcomes,
            status: "Transit drive failed for one or more squads."
        ) }
    }

    // MARK: - Monitor

    private func startMonitor(fleetLink: FleetLinkService, spawnDefaults: SimSpawnDefaults) {
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.monitorIntervalNs)
                await self.monitorTick(fleetLink: fleetLink, spawnDefaults: spawnDefaults)
            }
        }
    }

    private func stopMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func monitorTick(fleetLink: FleetLinkService, spawnDefaults: SimSpawnDefaults) async {
        guard phase == .running, let started = runStartedAt else { return }
        let elapsed = Date().timeIntervalSince(started)
        if elapsed >= Self.runTimeoutS {
            await finishWithTimeout()
            return
        }

        let mapOrigin = mapGeodeticOriginForRun ?? mapGeodeticOriginFallback(lab: lab)
        let now = Date()
        for plan in activePlans where !squadDriveFailed.contains(plan.squadID) {
            let hub = fleetLink.hubTelemetry(forVehicleID: plan.vehicleID)
            if let bounds = TrainingLabRunSafetyMonitor.mapBoundsViolation(
                plan: plan,
                hub: hub,
                mapGeodeticOrigin: mapOrigin,
                mapHalfExtentM: mapHalfExtentMForRun
            ) {
                await abortTransitRunForSafety(bounds)
                return
            }
            let routePath = transitPathsByVehicleID[plan.vehicleID]
                ?? TrainingLabTransitPathProgress.fallbackPath(for: plan)
            var track = safetyProgressTracks[plan.vehicleID]
            if let stuck = TrainingLabRunSafetyMonitor.stuckViolation(
                plan: plan,
                hub: hub,
                routePath: routePath,
                track: &track,
                runStartedAt: started,
                now: now
            ) {
                if let track { safetyProgressTracks[plan.vehicleID] = track }
                await abortTransitRunForSafety(stuck)
                return
            }
            if let track { safetyProgressTracks[plan.vehicleID] = track }
        }

        var squadOutcomes: [TrainingRunSquadOutcome] = []
        var allReachedEnd = true
        var allSquadsTerminal = true
        var learningReachedEnd = false
        let failFast = TrainingLabRunPreferences.failRunOnFirstSquadFailure

        for plan in activePlans {
            if squadDriveFailed.contains(plan.squadID) {
                allReachedEnd = false
                squadOutcomes.append(
                    TrainingRunSquadOutcome.failed(
                        squadID: plan.squadID,
                        code: .executionFailed,
                        message: "\(plan.squadLabel): drive to end zone failed."
                    )
                )
                continue
            }
            let hub = fleetLink.hubTelemetry(forVehicleID: plan.vehicleID)
            let vehicleOutcome = TrainingLabRunEndEvaluator.evaluate(
                entryID: plan.entryID,
                vehicleID: plan.vehicleID,
                hub: hub,
                goal: plan.layout.goal,
                episodeDurationS: elapsed,
                endSlot: plan.endSlot,
                mapGeodeticOrigin: mapGeodeticOriginForRun ?? mapGeodeticOriginFallback(lab: lab),
                requiresStrictEndSlotBox: plan.requiresStrictEndSlotBox
            )
            if vehicleOutcome.succeeded {
                squadOutcomes.append(
                    TrainingLabRunEndEvaluator.squadOutcome(
                        squadID: plan.squadID,
                        vehicleOutcomes: [vehicleOutcome]
                    )
                )
                if plan.role == .learning {
                    learningReachedEnd = true
                }
            } else {
                allReachedEnd = false
                allSquadsTerminal = false
                let code = TrainingLabRunEndEvaluator.failureCode(
                    hub: hub,
                    outcome: vehicleOutcome,
                    requiresStrictEndSlotBox: plan.requiresStrictEndSlotBox
                )
                squadOutcomes.append(
                    TrainingLabRunEndEvaluator.squadOutcome(
                        squadID: plan.squadID,
                        vehicleOutcomes: [vehicleOutcome],
                        failureCode: code,
                        operatorMessage: vehicleOutcome.detail
                            ?? "\(plan.squadLabel) has not reached the end slot."
                    )
                )
            }
        }

        statusText = String(
            format: "Transit run… %.0f s — driving to end formation.",
            elapsed
        )

        if failFast {
            guard allReachedEnd else { return }
            appendLog("Monitor: all squads within end-slot tolerance.")
            await completeRun(
                terminalPhase: .succeeded,
                squadOutcomes: squadOutcomes,
                status: "All squads reached end formation."
            )
            return
        }

        guard allSquadsTerminal else { return }
        appendLog("Monitor: all squads terminal — evaluating run outcome.")
        if learningReachedEnd {
            let otherFailures = squadOutcomes.filter { !$0.succeeded }.count
            let status = otherFailures == 0
                ? "Learning squad and all supporting squads reached end formation."
                : "Learning squad reached end formation; \(otherFailures) other squad(s) did not finish."
            await completeRun(terminalPhase: .succeeded, squadOutcomes: squadOutcomes, status: status)
        } else {
            await completeRun(
                terminalPhase: .failed,
                squadOutcomes: squadOutcomes,
                status: "Learning squad did not reach the end formation."
            )
        }
    }

    private func abortTransitRunForSafety(_ violation: TrainingLabRunSafetyMonitor.Violation) async {
        guard phase == .running else { return }
        appendLog("[Safety] \(violation.message)")
        let outcomes = activePlans.map { plan in
            if plan.vehicleID == violation.vehicleID {
                return TrainingRunSquadOutcome.failed(
                    squadID: plan.squadID,
                    code: violation.code,
                    message: violation.message
                )
            }
            return TrainingRunSquadOutcome.failed(
                squadID: plan.squadID,
                code: .aborted,
                message: "Run aborted — \(violation.message)"
            )
        }
        await completeRun(terminalPhase: .failed, squadOutcomes: outcomes, status: violation.message)
    }

    private func finishWithTimeout() async {
        appendLog("Monitor: run timed out after \(Int(Self.runTimeoutS)) s.")
        let outcomes = activePlans.map { plan in
            TrainingRunSquadOutcome.failed(
                squadID: plan.squadID,
                code: .timeout,
                message: "\(plan.squadLabel) did not reach the end zone in time."
            )
        }
        await completeRun(terminalPhase: .failed, squadOutcomes: outcomes, status: "Transit run timed out.")
    }

    private func completeRun(
        terminalPhase: TrainingRunPhase,
        squadOutcomes: [TrainingRunSquadOutcome],
        status: String
    ) async {
        guard Self.sessionAllowsCompletion(whileIn: phase) else { return }
        stopMonitor()
        stopGazeboProxyTelemetrySync()
        stopTransitDrive(fleetLink: lab?.teaching.fleetLinkForMapSession)
        let finishedAt = Date()
        let startedAt = runStartedAt
        let plans = activePlans
        let driveFailed = squadDriveFailed
        let paths = transitPathsByVehicleID
        let pathSources = pathSourceByVehicleID
        let tracks = safetyProgressTracks
        let learning = learningSquadID
        let fleetLink = lab?.teaching.fleetLinkForMapSession

        phase = terminalPhase
        result = TrainingRunResult(
            phase: terminalPhase,
            squadOutcomes: squadOutcomes,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        statusText = status
        appendLog(status)

        let snapshot = TrainingLabRunMetricsRecorder.makeSnapshot(
            result: result,
            statusMessage: status,
            plans: plans,
            squadOutcomes: squadOutcomes,
            squadDriveFailed: driveFailed,
            transitPathsByVehicleID: paths,
            pathSourceByVehicleID: pathSources,
            safetyProgressTracks: tracks,
            fleetLink: fleetLink,
            startedAt: startedAt,
            finishedAt: finishedAt,
            learningSquadID: learning
        )

        if let lab, let roster = boundRoster {
            await lab.finalizeTransitRun(
                snapshot: snapshot,
                roster: roster,
                appendRunLog: { [weak self] line in
                    self?.appendLog(line)
                }
            )
        }

        activePlans = []
        squadDriveFailed = []
        learningSquadID = nil
        runStartedAt = nil
        mapGeodeticOriginForRun = nil
        safetyProgressTracks = [:]
        transitPathsByVehicleID = [:]
        pathSourceByVehicleID = [:]
        resolvedPathsByVehicleID = [:]
        boundRoster = nil
        GuardianApplicationLifecycle.shared.endBackgroundLabRun()
    }

    private func mapGeodeticOriginFallback(lab: TrainingLabController?) -> SimSpawnDefaults {
        guard let environment = lab?.teaching.selectedEnvironment else { return .default }
        return TrainingLabMapSessionLifecycle.mapGeodeticOrigin(
            environment: environment,
            spawnDefaults: lab?.teaching.spawnDefaultsForMapSession ?? .default
        )
    }

    private func failRun(message: String, code: TrainingRunFailureCode) {
        phase = .failed
        result = TrainingRunResult(
            phase: .failed,
            squadOutcomes: [],
            startedAt: nil,
            finishedAt: Date()
        )
        statusText = message
        appendLog(message)
    }

    private func appendLog(_ message: String) {
        logLines.insert(TrainingPanelLogLine(message: message), at: 0)
        lab?.teaching.logMap("transit run: \(message)")
    }

    private func mapRunLogHandler() -> TrainingLabMapSessionDiagnostics.LogHandler {
        { [weak self] message in
            self?.appendLog("[Map] \(message)")
        }
    }
}

import Combine
import Foundation

/// Training lab **transit run** — all linked single-vehicle squads start zone → end zone (Phase 4c).
@MainActor
final class TrainingLabRunOrchestrator: ObservableObject {
    @Published private(set) var phase: TrainingRunPhase = .idle
    @Published private(set) var result: TrainingRunResult = .idle
    @Published private(set) var statusText: String = ""
    @Published private(set) var logLines: [TrainingPanelLogLine] = []

    private static let monitorIntervalNs: UInt64 = 1_000_000_000
    /// Whole-run wall clock cap. Phase 4d waypoints: consider pausing or excluding authorized
    /// per-waypoint **delay/dwell** from this budget (same policy as stuck — see Phase 4d checklist).
    private static let runTimeoutS: TimeInterval = 300

    private weak var lab: TrainingLabController?
    private var monitorTask: Task<Void, Never>?
    private var transitDriveTask: Task<Void, Never>?
    private var activePlans: [TrainingLabRunVehiclePlan] = []
    private var squadDriveFailed: Set<UUID> = []
    private var learningSquadID: UUID?
    private var runStartedAt: Date?
    private var mapGeodeticOriginForRun: SimSpawnDefaults?
    private var mapHalfExtentMForRun: Double = 500
    private var safetyProgressTracks: [String: TrainingLabRunSafetyMonitor.VehicleProgressTrack] = [:]
    /// Resolved drive polylines (Nav2 or geodesic) for along-path stuck detection.
    private var transitPathsByVehicleID: [String: [RouteCoordinate]] = [:]

    var isSessionActive: Bool {
        phase == .staged || phase == .running
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
            lab.teaching.applyTransitLayout(learningPlan.layout)
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
        appendLog("Map built. Driving squads to end zones (open-loop path follow).")

        for plan in activePlans {
            let path = await TrainingLabTransitMotion.resolvePath(fleetLink: fleetLink, plan: plan)
            transitPathsByVehicleID[plan.vehicleID] = path.points
            appendLog(
                "\(plan.squadLabel): route \(path.source.rawValue), \(path.points.count) pt — stuck uses along-path progress."
            )
        }
        appendLog(
            "Safety: map bounds enforced; stuck if no along-route progress for \(Int(TrainingLabRunSafetyMonitor.stuckNoProgressWindowS)) s (after \(Int(TrainingLabRunSafetyMonitor.stuckGraceAfterStartS)) s grace)."
        )

        GuardianApplicationLifecycle.shared.beginBackgroundLabRun()
        startMonitor(fleetLink: fleetLink, spawnDefaults: lab.teaching.spawnDefaultsForMapSession)
        startTransitDrive(fleetLink: fleetLink)
    }

    func stop(roster: TrainingLabRosterController) async {
        stopMonitor()
        stopTransitDrive(fleetLink: lab?.teaching.fleetLinkForMapSession)
        lab?.teaching.cancelTeaching()
        if let lab {
            await lab.stopActiveFormationSession()
        }
        if phase == .running || phase == .staged {
            appendLog("Stop requested — resetting map session.")
            await lab?.resetMap(roster: roster, runLog: mapRunLogHandler())
            let aborted = activePlans.map { plan in
                TrainingRunSquadOutcome.failed(
                    squadID: plan.squadID,
                    code: .aborted,
                    message: "Run stopped by operator."
                )
            }
            completeRun(phase: .failed, squadOutcomes: aborted, status: "Run stopped.")
        } else {
            phase = .idle
            result = .idle
            statusText = ""
        }
        activePlans = []
        squadDriveFailed = []
        learningSquadID = nil
        runStartedAt = nil
        mapGeodeticOriginForRun = nil
        safetyProgressTracks = [:]
        transitPathsByVehicleID = [:]
        GuardianApplicationLifecycle.shared.endBackgroundLabRun()
    }

    // MARK: - Transit drive (detached — fleet hops on ``FleetLinkService`` main actor)

    private func startTransitDrive(fleetLink: FleetLinkService) {
        transitDriveTask?.cancel()
        let plans = activePlans
        transitDriveTask = Task.detached(priority: .userInitiated) { [weak self] in
            await TrainingLabTransitMotion.runParallelSquadDrives(
                fleetLink: fleetLink,
                plans: plans,
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
        completeRun(
            phase: .failed,
            squadOutcomes: outcomes,
            status: "Transit drive failed for one or more squads."
        )
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
            finishWithTimeout()
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
                abortTransitRunForSafety(bounds)
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
                abortTransitRunForSafety(stuck)
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
            completeRun(
                phase: .succeeded,
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
            completeRun(phase: .succeeded, squadOutcomes: squadOutcomes, status: status)
        } else {
            completeRun(
                phase: .failed,
                squadOutcomes: squadOutcomes,
                status: "Learning squad did not reach the end formation."
            )
        }
    }

    private func abortTransitRunForSafety(_ violation: TrainingLabRunSafetyMonitor.Violation) {
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
        completeRun(phase: .failed, squadOutcomes: outcomes, status: violation.message)
    }

    private func finishWithTimeout() {
        appendLog("Monitor: run timed out after \(Int(Self.runTimeoutS)) s.")
        let outcomes = activePlans.map { plan in
            TrainingRunSquadOutcome.failed(
                squadID: plan.squadID,
                code: .timeout,
                message: "\(plan.squadLabel) did not reach the end zone in time."
            )
        }
        completeRun(phase: .failed, squadOutcomes: outcomes, status: "Transit run timed out.")
    }

    private func completeRun(
        phase: TrainingRunPhase,
        squadOutcomes: [TrainingRunSquadOutcome],
        status: String
    ) {
        stopMonitor()
        stopTransitDrive(fleetLink: lab?.teaching.fleetLinkForMapSession)
        self.phase = phase
        result = TrainingRunResult(
            phase: phase,
            squadOutcomes: squadOutcomes,
            startedAt: runStartedAt,
            finishedAt: Date()
        )
        statusText = status
        appendLog(status)
        activePlans = []
        learningSquadID = nil
        runStartedAt = nil
        mapGeodeticOriginForRun = nil
        safetyProgressTracks = [:]
        transitPathsByVehicleID = [:]
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

import Foundation

/// Default roadtest / teaching metrics capture for Training transit runs (Phase 7 instrumentation).
enum TrainingLabRunMetricsRecorder {
    /// Builds a snapshot from orchestrator state while hub poses and route progress are still valid.
    @MainActor
    static func makeSnapshot(
        result: TrainingRunResult,
        statusMessage: String,
        plans: [TrainingLabRunVehiclePlan],
        squadOutcomes: [TrainingRunSquadOutcome],
        squadDriveFailed: Set<UUID>,
        transitPathsByVehicleID: [String: [RouteCoordinate]],
        pathSourceByVehicleID: [String: TrainingNav2PlanPathResponse.Source],
        safetyProgressTracks: [String: TrainingLabRunSafetyMonitor.VehicleProgressTrack],
        fleetLink: FleetLinkService?,
        startedAt: Date?,
        finishedAt: Date,
        learningSquadID: UUID?
    ) -> TrainingLabRunCompletionSnapshot {
        let duration = finishedAt.timeIntervalSince(startedAt ?? finishedAt)
        let outcomeBySquad = Dictionary(uniqueKeysWithValues: squadOutcomes.map { ($0.squadID, $0) })
        let vehicles = plans.map { plan -> TrainingLabRunCompletionSnapshot.VehicleRow in
            let path = transitPathsByVehicleID[plan.vehicleID] ?? []
            let hub = fleetLink?.hubTelemetry(forVehicleID: plan.vehicleID)
            let score = TrainingSkillScorer.evaluate(
                hub: hub,
                goal: plan.layout.goal,
                episodeDurationS: duration,
                constraintViolations: []
            )
            return TrainingLabRunCompletionSnapshot.VehicleRow(
                vehicleID: plan.vehicleID,
                squadID: plan.squadID,
                squadLabel: plan.squadLabel,
                role: plan.role,
                pathSource: pathSourceByVehicleID[plan.vehicleID] ?? .unavailable,
                pathPointCount: path.count,
                bestAlongTrackM: safetyProgressTracks[plan.vehicleID]?.bestAlongTrackM,
                squadDriveFailed: squadDriveFailed.contains(plan.squadID),
                hubAtEnd: TrainingLabTransitMotionProof.snapshot(hub: hub),
                goalScore: score,
                squadOutcome: outcomeBySquad[plan.squadID]
            )
        }
        return TrainingLabRunCompletionSnapshot(
            result: result,
            statusMessage: statusMessage,
            episodeDurationS: duration,
            learningSquadID: learningSquadID,
            vehicles: vehicles
        )
    }

    /// Writes structured run-log lines; call custom hooks before this if you need raw hub access.
    static func record(
        _ snapshot: TrainingLabRunCompletionSnapshot,
        appendLog: (String) -> Void
    ) {
        appendLog(
            String(
                format: "[Metrics] Run %@ — %.1f s, %d squad(s).",
                snapshot.result.phase.rawValue,
                snapshot.episodeDurationS,
                snapshot.vehicles.count
            )
        )
        for row in snapshot.vehicles {
            let role = row.role == .learning ? "learning" : "supporting"
            let along = row.bestAlongTrackM.map { String(format: "%.1f m along route", $0) } ?? "along route n/a"
            let drive = row.squadDriveFailed ? "drive failed" : "drive ok"
            appendLog(
                String(
                    format: "[Metrics] %@ (%@): path %@ %d pt, %@, %@ — pos %.1f m hdg %.0f°%@.",
                    row.squadLabel,
                    role,
                    row.pathSource.rawValue,
                    row.pathPointCount,
                    along,
                    drive,
                    row.goalScore.positionErrorM,
                    row.goalScore.headingErrorDeg,
                    row.goalScore.succeeded ? " ✓" : ""
                )
            )
            appendLog("[Metrics] \(row.squadLabel) hub end: \(row.hubAtEnd.logLine).")
            if let outcome = row.squadOutcome, let code = outcome.failureCode {
                appendLog("[Metrics] \(row.squadLabel) outcome: \(code.rawValue) — \(outcome.operatorMessage ?? "")")
            }
        }
    }
}

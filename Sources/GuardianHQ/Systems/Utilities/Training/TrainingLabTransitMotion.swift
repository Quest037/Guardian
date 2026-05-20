import Foundation

/// Drives a single vehicle toward its end slot using Nav2 (or geodesic) path + open-loop training control (v1 UGV).
///
/// Squad drives run off the main actor; ``FleetLinkService`` is ``@MainActor`` — fleet I/O uses explicit main-actor hops.
enum TrainingLabTransitMotion {
    enum Failure: Error, LocalizedError, Sendable {
        case message(String)

        var errorDescription: String? {
            switch self {
            case .message(let text): text
            }
        }
    }

    /// Conservative UGV transit speed until Nav2 ``navigate_to_pose`` execution ships.
    static let defaultMaxSpeedMS: Double = 1.5

    struct PathResolution: Equatable, Sendable {
        var points: [RouteCoordinate]
        var source: TrainingNav2PlanPathResponse.Source
    }

    struct SquadDriveReport: Sendable, Equatable {
        let squadID: UUID
        let logLines: [String]
        let failureMessage: String?
    }

    // MARK: - Parallel coordinator (off main actor)

    /// Runs one detached drive per squad; ``deliverReport`` / ``finishWithFailures`` should hop to the main actor.
    nonisolated static func runParallelSquadDrives(
        fleetLink: FleetLinkService,
        plans: [TrainingLabRunVehiclePlan],
        deliverReport: @escaping @Sendable (SquadDriveReport) async -> Void,
        finishWithFailures: @escaping @Sendable () async -> Void
    ) async {
        await withTaskGroup(of: SquadDriveReport.self) { group in
            for plan in plans {
                group.addTask {
                    await driveSquad(fleetLink: fleetLink, plan: plan)
                }
            }
            for await report in group {
                await deliverReport(report)
            }
        }
        await finishWithFailures()
    }

    // MARK: - Single squad

    nonisolated static func driveSquad(
        fleetLink: FleetLinkService,
        plan: TrainingLabRunVehiclePlan
    ) async -> SquadDriveReport {
        await enrollPx4Sidecar(fleetLink: fleetLink, vehicleID: plan.vehicleID)
        let path = await resolvePath(fleetLink: fleetLink, plan: plan)
        let roleLabel = plan.role == .learning ? "Learning" : "Supporting"
        let pathLabel = path.points.count >= 2
            ? "\(path.source.rawValue), \(path.points.count) pts"
            : "no path"
        var logLines = ["\(plan.squadLabel) (\(roleLabel)): \(pathLabel) — driving."]
        let result = await executeOpenLoopFollow(
            fleetLink: fleetLink,
            plan: plan,
            path: path.points
        )
        switch result {
        case .success:
            logLines.append("\(plan.squadLabel): drive segments complete.")
            return SquadDriveReport(squadID: plan.squadID, logLines: logLines, failureMessage: nil)
        case .failure(let error):
            return SquadDriveReport(
                squadID: plan.squadID,
                logLines: logLines,
                failureMessage: error.localizedDescription
            )
        }
    }

    nonisolated static func resolvePath(
        fleetLink: FleetLinkService,
        plan: TrainingLabRunVehiclePlan
    ) async -> PathResolution {
        let response = await fetchNav2PlanPath(fleetLink: fleetLink, plan: plan)
        if response.points.count >= 2 {
            return PathResolution(points: response.points, source: response.source)
        }
        let fallback = TrainingGeodesicPathPlanner.plan(
            start: plan.layout.start,
            goal: plan.layout.goal
        )
        let source: TrainingNav2PlanPathResponse.Source =
            response.source == .unavailable ? .geodesicFallback : response.source
        return PathResolution(points: fallback, source: source)
    }

    /// Start training control stream, follow ``path`` with synthesized segments, then stop the stream.
    nonisolated static func executeOpenLoopFollow(
        fleetLink: FleetLinkService,
        plan: TrainingLabRunVehiclePlan,
        path: [RouteCoordinate]
    ) async -> Result<Void, Failure> {
        let segments = GuardianBrainPlannerSegmentSynthesis.segments(
            path: path,
            maxSpeedMS: defaultMaxSpeedMS,
            initialHeadingDeg: plan.layout.start.headingDeg
        )
        guard !segments.isEmpty else {
            return .failure(.message("No drive segments for \(plan.squadLabel) — path too short."))
        }
        return await runTrainingControlSegments(
            fleetLink: fleetLink,
            vehicleID: plan.vehicleID,
            squadLabel: plan.squadLabel,
            segments: segments
        )
    }

    @MainActor
    private static func enrollPx4Sidecar(fleetLink: FleetLinkService, vehicleID: String) {
        fleetLink.ensurePx4Ros2Sidecar(forVehicleID: vehicleID)
    }

    @MainActor
    private static func fetchNav2PlanPath(
        fleetLink: FleetLinkService,
        plan: TrainingLabRunVehiclePlan
    ) async -> TrainingNav2PlanPathResponse {
        await fleetLink.requestTrainingNav2PlanPath(
            vehicleID: plan.vehicleID,
            layout: plan.layout
        )
    }

    @MainActor
    private static func runTrainingControlSegments(
        fleetLink: FleetLinkService,
        vehicleID: String,
        squadLabel: String,
        segments: [TrainingControlSegment]
    ) async -> Result<Void, Failure> {
        guard await fleetLink.startTrainingControlStream(vehicleID: vehicleID) else {
            return .failure(.message("\(squadLabel): training control stream did not start."))
        }
        do {
            for segment in segments {
                try Task.checkCancellation()
                try await fleetLink.executeTrainingSegment(vehicleID: vehicleID, segment: segment)
            }
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
            return .success(())
        } catch is CancellationError {
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
            return .failure(.message("\(squadLabel): drive cancelled."))
        } catch {
            await fleetLink.stopTrainingControlStream(vehicleID: vehicleID)
            return .failure(.message("\(squadLabel): drive failed (\(error.localizedDescription))."))
        }
    }
}

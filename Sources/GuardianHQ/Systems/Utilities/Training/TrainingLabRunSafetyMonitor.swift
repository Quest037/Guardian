import Foundation

/// In-run safety checks for Training lab transit (map edge, progress / stuck along drive path).
enum TrainingLabRunSafetyMonitor {
    /// Grace after drive start before stuck detection arms.
    static let stuckGraceAfterStartS: TimeInterval = 20
    /// No meaningful progress along the route for this long → stuck auto-fail.
    ///
    /// **Phase 4d waypoints:** when per-waypoint **delay / dwell** jobs ship, this timer must **pause**
    /// for the whole dwell (vehicle is allowed to hold position without advancing along-track). Resume
    /// counting only after dwell completes — see ``ToDo/TrainingGazeboSimulationToDo.md`` Phase 4d.
    static let stuckNoProgressWindowS: TimeInterval = 45
    /// Must advance this far along the route polyline to reset the stuck window.
    static let stuckProgressEpsilonM: Double = 0.75

    struct Violation: Equatable, Sendable {
        var squadLabel: String
        var vehicleID: String
        var message: String
        var code: TrainingRunFailureCode
    }

    struct VehicleProgressTrack: Equatable, Sendable {
        /// Best ``alongTrackProgressM`` achieved on the resolved transit path.
        var bestAlongTrackM: Double
        var stagnantSince: Date?
    }

    /// Map-base square (ENU) — training run vehicles must stay inside the authored floor.
    static func isInsideMapFloor(
        hub: FleetHubVehicleTelemetry,
        mapGeodeticOrigin: SimSpawnDefaults,
        mapHalfExtentM: Double
    ) -> Bool {
        guard let lat = hub.latitudeDeg, let lon = hub.longitudeDeg else { return true }
        let task = TrainingTaskPose(
            latitudeDeg: lat,
            longitudeDeg: lon,
            headingDeg: 0,
            absoluteAltitudeM: mapGeodeticOrigin.altitudeM
        )
        let env = TrainingEnvironmentGeodesy.environmentPose(
            taskPose: task,
            origin: mapGeodeticOrigin
        )
        let floor = TrainingLabFormationSlotGeometry.mapFloor(halfExtentM: mapHalfExtentM)
        return floor.contains(x: env.xM, y: env.yM)
    }

    static func mapBoundsViolation(
        plan: TrainingLabRunVehiclePlan,
        hub: FleetHubVehicleTelemetry?,
        mapGeodeticOrigin: SimSpawnDefaults,
        mapHalfExtentM: Double
    ) -> Violation? {
        guard let hub else {
            return Violation(
                squadLabel: plan.squadLabel,
                vehicleID: plan.vehicleID,
                message: "\(plan.squadLabel): telemetry lost.",
                code: .commsLost
            )
        }
        guard isInsideMapFloor(
            hub: hub,
            mapGeodeticOrigin: mapGeodeticOrigin,
            mapHalfExtentM: mapHalfExtentM
        ) else {
            return Violation(
                squadLabel: plan.squadLabel,
                vehicleID: plan.vehicleID,
                message: "\(plan.squadLabel) left the training map bounds.",
                code: .constraintViolation
            )
        }
        return nil
    }

    /// Updates along-path progress; returns a violation when the vehicle is stuck on route.
    ///
    /// v1: ``stagnantSince`` runs whenever along-track progress stalls (no waypoint dwell yet).
    /// Phase 4d: skip / freeze this check while the active waypoint job is a timed delay/dwell.
    static func stuckViolation(
        plan: TrainingLabRunVehiclePlan,
        hub: FleetHubVehicleTelemetry?,
        routePath: [RouteCoordinate],
        track: inout VehicleProgressTrack?,
        runStartedAt: Date,
        now: Date = Date()
    ) -> Violation? {
        guard now.timeIntervalSince(runStartedAt) >= stuckGraceAfterStartS else { return nil }
        guard let hub,
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else { return nil }

        let path = routePath.count >= 2 ? routePath : TrainingLabTransitPathProgress.fallbackPath(for: plan)
        guard let alongM = TrainingLabTransitPathProgress.alongTrackProgressM(
            latitudeDeg: lat,
            longitudeDeg: lon,
            path: path
        ) else { return nil }

        if var existing = track {
            if alongM > existing.bestAlongTrackM + stuckProgressEpsilonM {
                existing.bestAlongTrackM = alongM
                existing.stagnantSince = nil
                track = existing
                return nil
            }
            if existing.stagnantSince == nil {
                existing.stagnantSince = now
                track = existing
                return nil
            }
            if now.timeIntervalSince(existing.stagnantSince!) >= stuckNoProgressWindowS {
                return Violation(
                    squadLabel: plan.squadLabel,
                    vehicleID: plan.vehicleID,
                    message: "\(plan.squadLabel) is stuck — no progress along the route for \(Int(stuckNoProgressWindowS)) s.",
                    code: .executionFailed
                )
            }
            track = existing
            return nil
        }

        track = VehicleProgressTrack(bestAlongTrackM: alongM, stagnantSince: nil)
        return nil
    }
}

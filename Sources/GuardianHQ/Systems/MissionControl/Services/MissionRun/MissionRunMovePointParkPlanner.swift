import Foundation

// MARK: - Errors

/// Planner-side failure before a ``recipe.fleet.do.move.point.park`` dispatch is queued.
enum MissionRunMovePointParkPlannerError: Error, Equatable {
    case noVehiclePosition
    case noEligibleOpenPoint(kind: MissionPointKind)
}

// MARK: - Nearest open point → recipe parameters (late binding)

/// Resolves the **nearest open** mission map point of a given ``MissionPointKind`` for MRE,
/// scoped to the slot's parent task **or** mission-wide points (`taskID == nil`). Intended to be
/// called **immediately before** enqueueing ``FleetMovePointParkRecipeRegistrations/movePointParkRecipeName``
/// so hub latitude/longitude/AGL stay fresh.
enum MissionRunMovePointParkPlanner: Sendable {

    /// Yaw for move+park recipes: prefer hub ``headingDeg`` (attitude), then ``yawDeg``.
    static func resolvedVehicleYawDeg(headingDeg: Double?, yawDeg: Double?) -> Double {
        headingDeg ?? yawDeg ?? 0
    }

    /// MC-R style one-liner, e.g. `Move to rally point [RP:1]` (matches ``MissionPoint/mapChipLabel``).
    static func procedureLogSummary(for point: MissionPoint) -> String {
        let kindWord = point.kind.rawValue
        return "Move to \(kindWord) point [\(point.mapChipLabel)]"
    }

    static func haversineMeters(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let earthRadiusM = 6_371_000.0
        let p1 = lat1 * .pi / 180
        let p2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(p1) * cos(p2) * sin(dLambda / 2) * sin(dLambda / 2)
        return 2 * earthRadiusM * asin(min(1, sqrt(a)))
    }

    /// Open points of `kind` belonging to `parentTaskID` **or** mission-wide (`taskID == nil`).
    static func eligibleOpenPoints(
        kind: MissionPointKind,
        parentTaskID: UUID,
        among points: [MissionPoint]
    ) -> [MissionPoint] {
        points.filter { candidate in
            guard !candidate.isClosed else { return false }
            guard candidate.kind == kind else { return false }
            if let tid = candidate.taskID {
                return tid == parentTaskID
            }
            return true
        }
    }

    /// Picks the closest eligible point to the vehicle (haversine on WGS84).
    static func nearestPoint(
        kind: MissionPointKind,
        parentTaskID: UUID,
        among points: [MissionPoint],
        vehicleLatDeg: Double,
        vehicleLonDeg: Double
    ) throws -> MissionPoint {
        let eligible = eligibleOpenPoints(kind: kind, parentTaskID: parentTaskID, among: points)
        guard let best = eligible.min(by: { a, b in
            let da = haversineMeters(
                lat1: vehicleLatDeg, lon1: vehicleLonDeg,
                lat2: a.coordinate.lat, lon2: a.coordinate.lon
            )
            let db = haversineMeters(
                lat1: vehicleLatDeg, lon1: vehicleLonDeg,
                lat2: b.coordinate.lat, lon2: b.coordinate.lon
            )
            return da < db
        }) else {
            throw MissionRunMovePointParkPlannerError.noEligibleOpenPoint(kind: kind)
        }
        return best
    }

    /// Parameter bundle for ``FleetMovePointParkRecipeRegistrations/movePointParkRecipeName``.
    ///
    /// - Parameters:
    ///   - currentRelativeAltitudeM: Pass hub **current** relative altitude (AGL-style) so the move
    ///     does not jump to a map-point altitude (surface / sub stay consistent).
    static func buildMovePointParkRecipeParameters(
        kind: MissionPointKind,
        parentTaskID: UUID,
        missionPoints: [MissionPoint],
        vehicleLatitudeDeg: Double?,
        vehicleLongitudeDeg: Double?,
        currentRelativeAltitudeM: Double,
        yawDeg: Double = 0
    ) throws -> FleetRecipeParameters {
        guard let vLat = vehicleLatitudeDeg, let vLon = vehicleLongitudeDeg else {
            throw MissionRunMovePointParkPlannerError.noVehiclePosition
        }
        let point = try nearestPoint(
            kind: kind,
            parentTaskID: parentTaskID,
            among: missionPoints,
            vehicleLatDeg: vLat,
            vehicleLonDeg: vLon
        )
        let summary = procedureLogSummary(for: point)
        return FleetRecipeParameters(values: [
            "procedureLogSummary": .string(summary),
            "pointKind": .string(FleetVehicleCoreCommandPointKind.explicit.rawValue),
            "latitudeDeg": .double(point.coordinate.lat),
            "longitudeDeg": .double(point.coordinate.lon),
            "relativeAltitudeM": .double(currentRelativeAltitudeM),
            "yawDeg": .double(yawDeg),
        ])
    }

    /// Explicit WGS84 target (e.g. MCS operator launch at **Start Run**).
    static func buildExplicitMovePointParkRecipeParameters(
        latitudeDeg: Double,
        longitudeDeg: Double,
        relativeAltitudeM: Double,
        yawDeg: Double = 0,
        procedureLogSummary: String
    ) throws -> FleetRecipeParameters {
        FleetRecipeParameters(values: [
            "procedureLogSummary": .string(procedureLogSummary),
            "pointKind": .string(FleetVehicleCoreCommandPointKind.explicit.rawValue),
            "latitudeDeg": .double(latitudeDeg),
            "longitudeDeg": .double(longitudeDeg),
            "relativeAltitudeM": .double(relativeAltitudeM),
            "yawDeg": .double(yawDeg),
        ])
    }
}

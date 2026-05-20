import Foundation

/// Convoy **assembly** readiness — wingmen on heading-based slots astern of the primary (`ToDo/SquadFollow&Formation.md` §C).
enum MissionRunSquadConvoyAssemblyUtilities {

    /// Horizontal distance from wingman to its convoy slot (m).
    static func distanceToSlotM(
        wingmanLatitudeDeg: Double,
        wingmanLongitudeDeg: Double,
        slot: RouteCoordinate
    ) -> Double {
        MissionTelemetryGeo.horizontalDistanceM(
            lat1: wingmanLatitudeDeg,
            lon1: wingmanLongitudeDeg,
            lat2: slot.lat,
            lon2: slot.lon
        )
    }

    /// True when every wingman with a live position is within ``MissionSquadConvoyFollowControlPolicy/convoyAssemblyArrivalM`` of its slot.
    static func isConvoyAssembled(
        targets: [(assignmentID: UUID, slot: RouteCoordinate)],
        wingmanPositionByAssignmentID: [UUID: (lat: Double, lon: Double)],
        arrivalM: Double = MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM
    ) -> Bool {
        guard !targets.isEmpty else { return true }
        for target in targets {
            guard let pos = wingmanPositionByAssignmentID[target.assignmentID] else { return false }
            if distanceToSlotM(
                wingmanLatitudeDeg: pos.lat,
                wingmanLongitudeDeg: pos.lon,
                slot: target.slot
            ) > arrivalM {
                return false
            }
        }
        return true
    }
}

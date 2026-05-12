import Foundation

// MARK: - Reserve swap reposition geometry

/// How the **reserve** vehicle is moved relative to the **vacancy (active)** before roster commit
/// (``MissionRosterReservesToDo.md`` swap pipeline — move reserve into position).
enum MissionRunReserveRepositionGeometryKind: String, Equatable, Codable, CaseIterable, Sendable {
    /// Offset from the active’s hub-reported position (local ENU-style **east** / **north** metres; executor maps to guided targets).
    case joinFormationOffset
    /// Fly to the active’s current **hold / orbit** anchor (same map + hub position source as MC-R).
    case rallyToActiveHoldPoint
    /// Skip reposition when reserve and active hub positions are within ``MissionRunReserveRepositionGeometryPolicy/colocatedHorizontalThresholdMeters`` (and optional vertical gate at executor).
    case replaceInPlaceIfColocated
}

/// East / north offset in metres for ``MissionRunReserveRepositionGeometryKind/joinFormationOffset``.
struct MissionRunReserveRepositionFormationOffset: Equatable, Sendable {
    var eastMeters: Double
    var northMeters: Double
}

/// Locked **v1** geometry selection for the reposition phase.
enum MissionRunReserveRepositionGeometryPolicy {

    /// When ``replaceInPlaceIfColocated`` is chosen, executor compares hub horizontal distance to this threshold.
    static let colocatedHorizontalThresholdMeters: Double = 75

    /// Default before colocation analysis runs: rally keeps separation predictable vs silent “no move”.
    static let defaultGeometryKind: MissionRunReserveRepositionGeometryKind = .rallyToActiveHoldPoint

    struct GeometryReadiness: Equatable, Sendable {
        var isReady: Bool
        var rejectionReason: String?

        static func ready() -> GeometryReadiness {
            GeometryReadiness(isReady: true, rejectionReason: nil)
        }

        static func rejected(_ reason: String) -> GeometryReadiness {
            GeometryReadiness(isReady: false, rejectionReason: reason)
        }
    }

    /// Validates inputs required before dispatching reposition commands for ``kind``.
    static func validateGeometryReadiness(
        kind: MissionRunReserveRepositionGeometryKind,
        formationOffset: MissionRunReserveRepositionFormationOffset?
    ) -> GeometryReadiness {
        switch kind {
        case .joinFormationOffset:
            guard let o = formationOffset else {
                return .rejected("Formation offset geometry requires formationOffset.")
            }
            guard o.eastMeters.isFinite, o.northMeters.isFinite else {
                return .rejected("Formation offset east/north metres must be finite.")
            }
            return .ready()
        case .rallyToActiveHoldPoint, .replaceInPlaceIfColocated:
            return .ready()
        }
    }
}

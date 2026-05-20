import Foundation

/// Squad formation group anchor inside a start or end zone (ENU metres on the training floor).
struct TrainingLabZoneFormationAnchor: Codable, Equatable, Sendable {
    var centerXM: Double
    var centerYM: Double
    var headingDeg: Double

    static func seeded(in zone: WorldBuilderZoneState) -> TrainingLabZoneFormationAnchor {
        TrainingLabZoneFormationAnchor(
            centerXM: zone.centerXM,
            centerYM: zone.centerYM,
            headingDeg: 0
        )
    }

    /// Default primary anchor for squad index 0…2 — one third of the zone each (room for up to six vehicles).
    static func defaultForSquadIndex(_ squadIndex: Int, in zone: WorldBuilderZoneState) -> TrainingLabZoneFormationAnchor {
        let idx = min(max(squadIndex, 0), 2)
        let cx = zone.centerXM
        let cy = zone.centerYM
        let r = max(zone.radiusM, 1)
        switch zone.shape {
        case .square:
            let bandXM = r * 0.55
            let bandOffsets: [Double] = [-bandXM, 0, bandXM]
            return TrainingLabZoneFormationAnchor(
                centerXM: cx + bandOffsets[idx],
                centerYM: cy,
                headingDeg: 0
            )
        case .circle:
            let distM = r * 0.5
            let angleDeg: [Double] = [-120, 0, 120]
            let radians = angleDeg[idx] * .pi / 180
            return TrainingLabZoneFormationAnchor(
                centerXM: cx + distM * sin(radians),
                centerYM: cy + distM * cos(radians),
                headingDeg: 0
            )
        }
    }
}

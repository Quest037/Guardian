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
}

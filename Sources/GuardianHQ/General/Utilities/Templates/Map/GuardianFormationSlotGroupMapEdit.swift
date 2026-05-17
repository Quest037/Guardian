import Foundation

/// Interactive formation slot-group chrome on the Leaflet map (Formations playground).
/// Center diamond translates the anchor; rim handle on the circle sets heading (fixed radius).
struct GuardianFormationSlotGroupMapEdit: Equatable, Sendable {
    var centerLat: Double
    var centerLon: Double
    var headingDeg: Double
    var circleRadiusM: Double
}

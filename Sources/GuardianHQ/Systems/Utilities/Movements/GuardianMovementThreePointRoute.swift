import Foundation

/// Pre-plotted carrots for one ``GuardianMovementID/threePointReverse`` attempt (reverse leg, then forward back to slot).
struct GuardianMovementThreePointRoute: Equatable, Sendable {
    let slot: RouteCoordinate
    let targetHeadingDeg: Double
    let reverseWaypoints: [RouteCoordinate]
    let forwardWaypoints: [RouteCoordinate]

    var allWaypoints: [RouteCoordinate] {
        reverseWaypoints + forwardWaypoints
    }
}

import Foundation

/// Result of a Training A→B plan request via the ROS 2 bridge (Nav2 or geodesic fallback).
struct TrainingNav2PlanPathResponse: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case nav2
        case geodesicFallback = "geodesic_fallback"
        case error
        case unavailable
    }

    var points: [RouteCoordinate]
    var source: Source
    var message: String?

    static let unavailable = TrainingNav2PlanPathResponse(
        points: [],
        source: .unavailable,
        message: nil
    )
}

import Foundation

/// Leg within a ``GuardianMovementID/threePointReverse`` (or forward-start variant) sequence.
enum GuardianMovementThreePointPhase: String, Codable, Sendable, Equatable {
    case reverseLeg
    case forwardLeg
}

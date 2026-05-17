import Foundation

/// Outcome of a single in-slot ``GuardianMovementID/threePointReverse`` attempt (no auto-retry).
enum GuardianMovementThreePointSequenceStatus: String, Codable, Sendable, Equatable {
    case running
    case succeeded
    case failed
}

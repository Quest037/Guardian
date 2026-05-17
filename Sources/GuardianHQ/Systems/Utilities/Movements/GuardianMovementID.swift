import Foundation

/// Stable catalogue id for a vehicle movement primitive (formation, MRE, Live Drive helpers).
enum GuardianMovementID: String, Codable, Sendable, CaseIterable, Equatable {
    case forwardPursuit = "movement.forwardPursuit"
    case reverse = "movement.reverse"
    /// In-slot UGV heading: reverse leg then forward leg (non-holonomic).
    case threePointReverse = "movement.3point.reverse"
    /// In-slot UGV heading: forward leg then reverse leg (reserved — same sequencer, different start).
    case threePointForward = "movement.3point.forward"
    /// Lateral body translation (holonomic / copter). Not available on wheeled or tracked UGV.
    case strafe = "movement.strafe"

    var displayTitle: String {
        switch self {
        case .forwardPursuit: return "Forward pursuit"
        case .reverse: return "Reverse (steered)"
        case .threePointReverse: return "3-point turn (reverse first)"
        case .threePointForward: return "3-point turn (forward first)"
        case .strafe: return "Strafe"
        }
    }

    /// Body-frame OFFBOARD / Guided rates must be streamed (PX4 UGV cannot yaw-in-place on position hold alone).
    var prefersVelocityBodyExecution: Bool {
        switch self {
        case .forwardPursuit, .strafe:
            return false
        case .reverse, .threePointReverse, .threePointForward:
            return true
        }
    }
}

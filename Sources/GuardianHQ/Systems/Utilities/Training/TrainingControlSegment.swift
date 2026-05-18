import Foundation

/// One open-loop body command for a fixed duration (training lab v1 actuator primitive).
struct TrainingControlSegment: Codable, Equatable, Sendable, Hashable {
    var bodyForwardMS: Float = 0
    var bodyRightMS: Float = 0
    var yawspeedDegS: Float = 0
    var climbRateMS: Float = 0
    /// Wall-clock duration for this segment (s).
    var durationS: Double

    static func forward(_ speedMS: Float, durationS: Double) -> TrainingControlSegment {
        TrainingControlSegment(bodyForwardMS: speedMS, durationS: durationS)
    }

    static func reverse(_ speedMS: Float, durationS: Double) -> TrainingControlSegment {
        TrainingControlSegment(bodyForwardMS: -abs(speedMS), durationS: durationS)
    }

    static func yaw(_ rateDegS: Float, durationS: Double) -> TrainingControlSegment {
        TrainingControlSegment(yawspeedDegS: rateDegS, durationS: durationS)
    }

    static func hold(durationS: Double) -> TrainingControlSegment {
        TrainingControlSegment(durationS: durationS)
    }
}

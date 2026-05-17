import Foundation

/// Tuning for ``GuardianMovementID/reverse`` — astern speed plus steered yaw (not straight-line only).
enum GuardianMovementReversePolicy {
    static let lateralSteerGainDegSPerM: Double = 14.0
    static let bearingSteerGainDegSPerDeg: Double = 0.32
    static let headingAlignScale: Double = 1.05
}

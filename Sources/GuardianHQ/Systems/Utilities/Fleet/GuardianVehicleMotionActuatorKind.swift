import Foundation

/// Which low-level actuator interprets high-level drive commands (forward, reverse, yaw).
enum GuardianVehicleMotionActuatorKind: Equatable, Sendable {
    /// ``Offboard/setVelocityBody`` — ArduPilot GUIDED rovers, PX4 copters/subs, etc.
    case offboardBodyVelocity
    /// PX4 Ackermann/differential rover: ``ManualControl`` throttle + steering (same as Live Drive S).
    /// Generic body velocity OFFBOARD is ignored or misinterpreted on PX4 rovers.
    case px4GroundThrottleSteering
}

enum GuardianVehicleMotionActuatorRouting {
    static func kind(
        stack: FleetAutopilotStack,
        universalClass: UniversalVehicleClass
    ) -> GuardianVehicleMotionActuatorKind {
        if stack == .px4, universalClass == .ugv {
            return .px4GroundThrottleSteering
        }
        return .offboardBodyVelocity
    }
}

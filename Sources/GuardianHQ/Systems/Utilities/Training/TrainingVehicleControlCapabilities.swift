import Foundation

/// Which training controls a vehicle class may use; validates segments against forbidden set.
enum TrainingVehicleControlCapabilities {
    static func supportedAxes(vehicleType: FleetVehicleType) -> Set<TrainingControlAxis> {
        Set(TrainingControlAxis.supported(for: vehicleType))
    }

    static func supports(_ axis: TrainingControlAxis, vehicleType: FleetVehicleType) -> Bool {
        supportedAxes(vehicleType: vehicleType).contains(axis)
    }

    /// Controls this segment uses that are unsupported or forbidden.
    static func validateSegment(
        _ segment: TrainingControlSegment,
        vehicleType: FleetVehicleType,
        forbidden: Set<TrainingControlAxis>
    ) -> [TrainingControlAxis] {
        var violations: [TrainingControlAxis] = []
        let supported = supportedAxes(vehicleType: vehicleType)

        if segment.bodyForwardMS > 0.02 {
            if forbidden.contains(.driveForward) { violations.append(.driveForward) }
            if !supported.contains(.driveForward) { violations.append(.driveForward) }
        }
        if segment.bodyForwardMS < -0.02 {
            if forbidden.contains(.driveReverse) { violations.append(.driveReverse) }
            if !supported.contains(.driveReverse) { violations.append(.driveReverse) }
        }
        if segment.bodyRightMS > 0.02 {
            if forbidden.contains(.strafeRight) || !supported.contains(.strafeRight) {
                violations.append(.strafeRight)
            }
        }
        if segment.bodyRightMS < -0.02 {
            if !supported.contains(.strafeRight) { violations.append(.strafeRight) }
        }
        if segment.yawspeedDegS > 0.5 {
            if forbidden.contains(.turnClockwise) { violations.append(.turnClockwise) }
            if !supported.contains(.turnClockwise) { violations.append(.turnClockwise) }
        }
        if segment.yawspeedDegS < -0.5 {
            if forbidden.contains(.turnCounterClockwise) { violations.append(.turnCounterClockwise) }
            if !supported.contains(.turnCounterClockwise) { violations.append(.turnCounterClockwise) }
        }
        if abs(segment.climbRateMS) > 0.02 {
            if forbidden.contains(.climb) || !supported.contains(.climb) {
                violations.append(.climb)
            }
        }
        return violations
    }
}

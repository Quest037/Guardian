import Foundation

/// Synthesizes open-loop training segments from a planned path (planner-only brain packs in MRE).
enum GuardianBrainPlannerSegmentSynthesis {
    private static let yawRateDegS: Float = 22
    private static let minLegM = 0.35
    private static let minYawDeg = 8.0
    private static let maxSegmentDurationS = 8.0

    static func segments(
    path: [RouteCoordinate],
    maxSpeedMS: Double,
    initialHeadingDeg: Double
    ) -> [TrainingControlSegment] {
        guard path.count >= 2, maxSpeedMS > 0 else { return [] }
        let speed = Float(maxSpeedMS)
        var segments: [TrainingControlSegment] = []
        var headingDeg = initialHeadingDeg

        for index in 1..<path.count {
            let from = path[index - 1]
            let to = path[index]
            let bearing = MissionTelemetryGeo.bearingDegrees(
                lat1: from.lat,
                lon1: from.lon,
                lat2: to.lat,
                lon2: to.lon
            )
            let yawErr = MissionTelemetryGeo.angleDifferenceDeg(bearing, headingDeg)
            if abs(yawErr) >= minYawDeg {
                let rate: Float = yawErr >= 0 ? yawRateDegS : -yawRateDegS
                let duration = min(abs(yawErr) / Double(yawRateDegS), maxSegmentDurationS)
                segments.append(.yaw(rate, durationS: duration))
                headingDeg = bearing
            }
            let distM = MissionTelemetryGeo.horizontalDistanceM(
                lat1: from.lat,
                lon1: from.lon,
                lat2: to.lat,
                lon2: to.lon
            )
            if distM >= minLegM {
                let duration = min(distM / maxSpeedMS, maxSegmentDurationS)
                segments.append(.forward(speed, durationS: duration))
            }
        }
        return segments.filter { $0.durationS > 0 }
    }
}

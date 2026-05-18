import Foundation

/// Scores an episode against a training task goal.
enum TrainingSkillScorer {
    static let defaultArrivalM: Double = MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM
    static let defaultHeadingToleranceDeg: Double =
        MissionSquadConvoyFollowControlPolicy.convoyAssemblyHeadingToleranceDeg

    static func evaluate(
        hub: FleetHubVehicleTelemetry?,
        goal: TrainingTaskPose,
        episodeDurationS: Double,
        constraintViolations: Set<TrainingControlAxis>,
        arrivalM: Double = defaultArrivalM,
        headingToleranceDeg: Double = defaultHeadingToleranceDeg,
        requireHeading: Bool = true
    ) -> TrainingSkillScore {
        guard let hub,
              let lat = hub.latitudeDeg,
              let lon = hub.longitudeDeg
        else {
            return TrainingSkillScore(
                positionErrorM: .infinity,
                headingErrorDeg: .infinity,
                episodeDurationS: episodeDurationS,
                constraintViolations: Array(constraintViolations),
                succeeded: false
            )
        }

        let positionErrorM = MissionTelemetryGeo.horizontalDistanceM(
            lat1: lat,
            lon1: lon,
            lat2: goal.latitudeDeg,
            lon2: goal.longitudeDeg
        )
        let headingErrorDeg = abs(
            MissionSquadFormationHeadingPolicy.headingErrorDeg(
                hub: hub,
                targetHeadingDeg: goal.headingDeg
            ) ?? 180
        )
        let positionOk = positionErrorM <= arrivalM
        let headingOk = !requireHeading
            || MissionSquadFormationHeadingPolicy.isHeadingAligned(
                hub: hub,
                targetHeadingDeg: goal.headingDeg,
                toleranceDeg: headingToleranceDeg
            )
        let constraintsOk = constraintViolations.isEmpty
        let succeeded = positionOk && headingOk && constraintsOk

        return TrainingSkillScore(
            positionErrorM: positionErrorM,
            headingErrorDeg: headingErrorDeg,
            episodeDurationS: episodeDurationS,
            constraintViolations: Array(constraintViolations),
            succeeded: succeeded
        )
    }

    /// Lower is better (for picking best failed trial).
    static func sortKey(_ score: TrainingSkillScore) -> Double {
        if score.succeeded { return -score.episodeDurationS }
        return score.positionErrorM + score.headingErrorDeg * 0.05 + Double(score.constraintViolations.count) * 5
    }
}

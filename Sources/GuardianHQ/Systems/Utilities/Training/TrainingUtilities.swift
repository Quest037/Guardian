import Foundation

@MainActor
final class TrainingUtilities {
    func taskLayout(start: TrainingTaskPose, goal: TrainingTaskPose) -> TrainingTaskLayout {
        TrainingTaskLayoutFactory.layout(start: start, goal: goal)
    }

    func candidates(
        task: TrainingTaskKind,
        layout: TrainingTaskLayout,
        vehicleType: FleetVehicleType,
        forbidden: Set<TrainingControlAxis>,
        maxTrials: Int = TrainingSkillSearcher.defaultMaxTrials
    ) -> [TrainingSkillCandidate] {
        TrainingSkillSearcher.candidates(
            task: task,
            layout: layout,
            vehicleType: vehicleType,
            forbidden: forbidden,
            maxTrials: maxTrials
        )
    }

    func score(
        hub: FleetHubVehicleTelemetry?,
        goal: TrainingTaskPose,
        episodeDurationS: Double,
        constraintViolations: Set<TrainingControlAxis>
    ) -> TrainingSkillScore {
        TrainingSkillScorer.evaluate(
            hub: hub,
            goal: goal,
            episodeDurationS: episodeDurationS,
            constraintViolations: constraintViolations
        )
    }

    func supportedAxes(vehicleType: FleetVehicleType) -> Set<TrainingControlAxis> {
        TrainingVehicleControlCapabilities.supportedAxes(vehicleType: vehicleType)
    }
}

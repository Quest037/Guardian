import Foundation

/// Immutable transit-run evidence captured **after** the run result is published and **before**
/// ``TrainingLabMapSessionLifecycle/resetMap`` restores start poses (hook point for metrics / teaching).
struct TrainingLabRunCompletionSnapshot: Equatable, Sendable {
    struct VehicleRow: Equatable, Sendable {
        var vehicleID: String
        var squadID: UUID
        var squadLabel: String
        var role: TrainingLabRunVehiclePlan.SquadRole
        var pathSource: TrainingNav2PlanPathResponse.Source
        var pathPointCount: Int
        var bestAlongTrackM: Double?
        var squadDriveFailed: Bool
        var hubAtEnd: TrainingLabTransitMotionProof.Snapshot
        var goalScore: TrainingSkillScore
        var squadOutcome: TrainingRunSquadOutcome?
    }

    var result: TrainingRunResult
    var statusMessage: String
    var episodeDurationS: Double
    var learningSquadID: UUID?
    var vehicles: [VehicleRow]
}

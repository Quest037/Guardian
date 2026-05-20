import Foundation

/// Operator-visible phase for a squad **transit** run (start zone → end zone). Teach trials and formation-demo sessions use other controllers until the orchestrator lands (``ToDo/TrainingGazeboSimulationToDo.md`` Phase 4c).
enum TrainingRunPhase: String, Codable, Sendable, Equatable {
    case idle
    case staged
    case running
    case succeeded
    case failed
}

/// Typed failure reasons for transit runs and pre-Run staging.
enum TrainingRunFailureCode: String, Codable, Sendable, Equatable, CaseIterable {
    case stagingInvalid
    case nav2Unavailable
    case plannerFailed
    case executionFailed
    case timeout
    case commsLost
    case constraintViolation
    case endPositionMiss
    case endHeadingMiss
    case endFormationMismatch
    case aborted

    var operatorTitle: String {
        switch self {
        case .stagingInvalid: return "Setup invalid"
        case .nav2Unavailable: return "Nav2 unavailable"
        case .plannerFailed: return "Path planning failed"
        case .executionFailed: return "Autonomy failed"
        case .timeout: return "Timed out"
        case .commsLost: return "Vehicle link lost"
        case .constraintViolation: return "Control constraint violated"
        case .endPositionMiss: return "End position not reached"
        case .endHeadingMiss: return "End heading not reached"
        case .endFormationMismatch: return "End formation not achieved"
        case .aborted: return "Run stopped"
        }
    }
}

/// One vehicle row at end-of-run evaluation.
struct TrainingRunVehicleOutcome: Equatable, Sendable {
    var entryID: UUID
    var vehicleID: String?
    var positionErrorM: Double
    var headingErrorDeg: Double
    var succeeded: Bool
    /// Set when monitor uses strict end-slot box validation; `nil` for centre-arrival (auto end formation).
    var insideEndSlotBox: Bool?
    var detail: String?
}

/// Squad-level rollup for a transit run.
struct TrainingRunSquadOutcome: Equatable, Sendable {
    var squadID: UUID
    var vehicleOutcomes: [TrainingRunVehicleOutcome]
    var succeeded: Bool
    var failureCode: TrainingRunFailureCode?
    var operatorMessage: String?

    static func failed(
        squadID: UUID,
        code: TrainingRunFailureCode,
        message: String,
        vehicles: [TrainingRunVehicleOutcome] = []
    ) -> TrainingRunSquadOutcome {
        TrainingRunSquadOutcome(
            squadID: squadID,
            vehicleOutcomes: vehicles,
            succeeded: false,
            failureCode: code,
            operatorMessage: message
        )
    }
}

/// Full lab transit run result (one map session execution).
struct TrainingRunResult: Equatable, Sendable {
    var phase: TrainingRunPhase
    var squadOutcomes: [TrainingRunSquadOutcome]
    var startedAt: Date?
    var finishedAt: Date?

    /// Run met its completion phase (per-squad rows may still show failures when the operator allows other squads to continue).
    var succeeded: Bool {
        phase == .succeeded
    }

    static let idle = TrainingRunResult(phase: .idle, squadOutcomes: [], startedAt: nil, finishedAt: nil)
}

enum TrainingRunOutcomeFormatting {
    static func operatorMessage(from stagingIssues: [TrainingLabFormationSlotStaging.Issue]) -> String {
        stagingIssues.map(\.message).joined(separator: " ")
    }
}

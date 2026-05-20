import XCTest
@testable import GuardianCore

final class TrainingRunModelsTests: XCTestCase {

    func test_idle_result_not_succeeded() {
        XCTAssertFalse(TrainingRunResult.idle.succeeded)
        XCTAssertEqual(TrainingRunResult.idle.phase, .idle)
    }

    func test_succeeded_follows_run_phase_not_per_squad_rows() {
        let squadID = UUID()
        let ok = TrainingRunResult(
            phase: .succeeded,
            squadOutcomes: [
                TrainingRunSquadOutcome(
                    squadID: squadID,
                    vehicleOutcomes: [],
                    succeeded: true,
                    failureCode: nil,
                    operatorMessage: nil
                ),
            ],
            startedAt: Date(),
            finishedAt: Date()
        )
        XCTAssertTrue(ok.succeeded)

        let learningOKSupportingMiss = TrainingRunResult(
            phase: .succeeded,
            squadOutcomes: [
                TrainingRunSquadOutcome.failed(
                    squadID: UUID(),
                    code: .endPositionMiss,
                    message: "Missed end slot."
                ),
            ],
            startedAt: nil,
            finishedAt: nil
        )
        XCTAssertTrue(learningOKSupportingMiss.succeeded)

        let failedPhase = TrainingRunResult(
            phase: .failed,
            squadOutcomes: [],
            startedAt: nil,
            finishedAt: nil
        )
        XCTAssertFalse(failedPhase.succeeded)
    }

    func test_staging_message_joins_issues() {
        let msg = TrainingRunOutcomeFormatting.operatorMessage(from: [
            TrainingLabFormationSlotStaging.Issue(message: "No start zone."),
            TrainingLabFormationSlotStaging.Issue(message: "Alpha overlaps."),
        ])
        XCTAssertTrue(msg.contains("No start zone."))
        XCTAssertTrue(msg.contains("Alpha overlaps."))
    }
}

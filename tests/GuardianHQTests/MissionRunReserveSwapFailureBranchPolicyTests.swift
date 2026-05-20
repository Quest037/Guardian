import XCTest

@testable import GuardianCore

final class MissionRunReserveSwapFailureBranchPolicyTests: XCTestCase {

    private let maxRetries = MissionRunReserveSwapFailureBranchPolicy.maxAutomaticRetriesAfterFirstFailureSameCandidatePerGate

    func test_zero_failures_requests_retry_same() {
        let d = MissionRunReserveSwapFailureBranchPolicy.disposition(
            phase: .swapTimeChecks,
            consecutiveFailedGateAttemptsOnCurrentCandidate: 0,
            hasAnotherRankedCandidate: false,
            operatorPromptChannelAvailable: false
        )
        XCTAssertEqual(d, .retrySameCandidate)
    }

    func test_retries_until_cap_then_next_candidate() {
        let phases: [MissionRunReserveSwapPipelinePhase] = [.pickReserve, .swapTimeChecks, .missionUpload, .reposition]
        for phase in phases {
            for failureCount in 1 ... maxRetries {
                let d = MissionRunReserveSwapFailureBranchPolicy.disposition(
                    phase: phase,
                    consecutiveFailedGateAttemptsOnCurrentCandidate: failureCount,
                    hasAnotherRankedCandidate: true,
                    operatorPromptChannelAvailable: true
                )
                XCTAssertEqual(d, .retrySameCandidate, "phase=\(phase) failures=\(failureCount)")
            }
            let exhausted = MissionRunReserveSwapFailureBranchPolicy.disposition(
                phase: phase,
                consecutiveFailedGateAttemptsOnCurrentCandidate: 1 + maxRetries,
                hasAnotherRankedCandidate: true,
                operatorPromptChannelAvailable: true
            )
            XCTAssertEqual(exhausted, .tryNextCandidate, "phase=\(phase)")
        }
    }

    func test_exhausted_no_other_candidate_escalates_when_prompt_available() {
        let d = MissionRunReserveSwapFailureBranchPolicy.disposition(
            phase: .missionUpload,
            consecutiveFailedGateAttemptsOnCurrentCandidate: 1 + maxRetries,
            hasAnotherRankedCandidate: false,
            operatorPromptChannelAvailable: true
        )
        XCTAssertEqual(d, .escalateToOperatorPrompt)
    }

    func test_exhausted_no_other_candidate_aborts_when_no_prompt_channel() {
        let d = MissionRunReserveSwapFailureBranchPolicy.disposition(
            phase: .missionUpload,
            consecutiveFailedGateAttemptsOnCurrentCandidate: 1 + maxRetries,
            hasAnotherRankedCandidate: false,
            operatorPromptChannelAvailable: false
        )
        XCTAssertEqual(d, .abortSwapPreserveCommittedState)
    }

    func test_roster_commit_post_commit_and_displaced_clear_always_abort_regardless_of_counts() {
        for phase in [
            MissionRunReserveSwapPipelinePhase.rosterCommit,
            .postCommitHandoff,
            .displacedMissionClear,
            .displacedFleetWindDown,
        ] {
            for failures in 0 ... 5 {
                let d = MissionRunReserveSwapFailureBranchPolicy.disposition(
                    phase: phase,
                    consecutiveFailedGateAttemptsOnCurrentCandidate: failures,
                    hasAnotherRankedCandidate: true,
                    operatorPromptChannelAvailable: true
                )
                XCTAssertEqual(d, .abortSwapPreserveCommittedState, "phase=\(phase) failures=\(failures)")
            }
        }
    }
}

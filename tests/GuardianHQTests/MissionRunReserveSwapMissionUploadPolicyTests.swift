import XCTest

@testable import GuardianHQ

final class MissionRunReserveSwapMissionUploadPolicyTests: XCTestCase {

    func test_default_slice_is_full_task() {
        XCTAssertEqual(MissionRunReserveSwapMissionUploadPolicy.defaultSliceKind, .fullTaskMission)
    }

    func test_full_task_always_validates() {
        let v = MissionRunReserveSwapMissionUploadPolicy.validate(slice: .fullTaskMission, partialCursor: nil)
        XCTAssertTrue(v.allowsDispatch)
        XCTAssertNil(v.rejectionReason)
    }

    func test_partial_rejects_without_cursor() {
        let v = MissionRunReserveSwapMissionUploadPolicy.validate(slice: .partialFromActiveExecutionCursor, partialCursor: nil)
        XCTAssertFalse(v.allowsDispatch)
        XCTAssertNotNil(v.rejectionReason)
    }

    func test_partial_rejects_incomplete_cursor() {
        let v = MissionRunReserveSwapMissionUploadPolicy.validate(
            slice: .partialFromActiveExecutionCursor,
            partialCursor: MissionRunReserveMissionPartialCursor(missionProgressCurrent: 1, missionProgressTotal: nil, taskCycleIndex: nil)
        )
        XCTAssertFalse(v.allowsDispatch)
    }

    func test_partial_rejects_when_current_out_of_range() {
        let v = MissionRunReserveSwapMissionUploadPolicy.validate(
            slice: .partialFromActiveExecutionCursor,
            partialCursor: MissionRunReserveMissionPartialCursor(missionProgressCurrent: 5, missionProgressTotal: 3, taskCycleIndex: 0)
        )
        XCTAssertFalse(v.allowsDispatch)
    }

    func test_partial_accepts_valid_cursor() {
        let v = MissionRunReserveSwapMissionUploadPolicy.validate(
            slice: .partialFromActiveExecutionCursor,
            partialCursor: MissionRunReserveMissionPartialCursor(missionProgressCurrent: 0, missionProgressTotal: 4, taskCycleIndex: 1)
        )
        XCTAssertTrue(v.allowsDispatch)
        XCTAssertNil(v.rejectionReason)
    }

    func test_default_active_synchronisation_is_hard_pause() {
        XCTAssertEqual(
            MissionRunReserveSwapMissionUploadPolicy.defaultActiveSynchronisationKind,
            .hardPauseActiveUntilUploadCompletes
        )
    }

    func test_synchronisation_kind_case_count() {
        XCTAssertEqual(MissionRunReserveMissionUploadActiveSynchronisationKind.allCases.count, 2)
    }

    func test_default_upload_verification_is_count_readback() {
        XCTAssertEqual(MissionRunReserveSwapMissionUploadPolicy.defaultUploadVerificationKind, .missionItemCountReadback)
    }

    func test_verification_count_requires_expected_count() {
        let bad = MissionRunReserveSwapMissionUploadPolicy.validateVerificationReadiness(
            kind: .missionItemCountReadback,
            expectation: nil
        )
        XCTAssertFalse(bad.isReady)
        let good = MissionRunReserveSwapMissionUploadPolicy.validateVerificationReadiness(
            kind: .missionItemCountReadback,
            expectation: MissionRunReserveMissionUploadVerificationExpectation(expectedMissionItemCount: 7, expectedContentHash: nil, missionReadyRecipeRaw: nil)
        )
        XCTAssertTrue(good.isReady)
    }

    func test_verification_hash_requires_non_empty_string() {
        let bad = MissionRunReserveSwapMissionUploadPolicy.validateVerificationReadiness(
            kind: .missionPlanContentHashMatch,
            expectation: MissionRunReserveMissionUploadVerificationExpectation(expectedMissionItemCount: nil, expectedContentHash: "  ", missionReadyRecipeRaw: nil)
        )
        XCTAssertFalse(bad.isReady)
    }

    func test_verification_recipe_requires_valid_recipe_name() {
        let bad = MissionRunReserveSwapMissionUploadPolicy.validateVerificationReadiness(
            kind: .recipeBasedMissionReadyProbe,
            expectation: MissionRunReserveMissionUploadVerificationExpectation(expectedMissionItemCount: nil, expectedContentHash: nil, missionReadyRecipeRaw: "not-a-recipe")
        )
        XCTAssertFalse(bad.isReady)
        let good = MissionRunReserveSwapMissionUploadPolicy.validateVerificationReadiness(
            kind: .recipeBasedMissionReadyProbe,
            expectation: MissionRunReserveMissionUploadVerificationExpectation(
                expectedMissionItemCount: nil,
                expectedContentHash: nil,
                missionReadyRecipeRaw: "recipe.fleet.diagnose.armprobe"
            )
        )
        XCTAssertTrue(good.isReady)
    }

    func test_default_upload_failure_disposition_is_strict() {
        XCTAssertEqual(
            MissionRunReserveSwapMissionUploadPolicy.defaultUploadFailureDispositionKind,
            .strictBlockUntilUploadAndVerificationSucceed
        )
    }

    func test_degraded_handoff_rejected_under_strict_policy() {
        let a = MissionRunReserveMissionUploadDegradedHandoffAttestation(
            acknowledgmentSummary: "Proceed without full mission",
            missionRunID: UUID()
        )
        let r = MissionRunReserveSwapMissionUploadPolicy.validateDegradedHandoffPrerequisites(
            failureDisposition: .strictBlockUntilUploadAndVerificationSucceed,
            operatorAttestation: a
        )
        XCTAssertFalse(r.isReady)
    }

    func test_degraded_handoff_requires_attestation_when_allowed() {
        let r = MissionRunReserveSwapMissionUploadPolicy.validateDegradedHandoffPrerequisites(
            failureDisposition: .allowDegradedHandoffAfterOperatorConfirmation,
            operatorAttestation: nil
        )
        XCTAssertFalse(r.isReady)
        let badSummary = MissionRunReserveMissionUploadDegradedHandoffAttestation(
            acknowledgmentSummary: "   ",
            missionRunID: UUID()
        )
        let r2 = MissionRunReserveSwapMissionUploadPolicy.validateDegradedHandoffPrerequisites(
            failureDisposition: .allowDegradedHandoffAfterOperatorConfirmation,
            operatorAttestation: badSummary
        )
        XCTAssertFalse(r2.isReady)
        let ok = MissionRunReserveMissionUploadDegradedHandoffAttestation(
            acknowledgmentSummary: "Operator accepts partial mission",
            missionRunID: UUID()
        )
        let r3 = MissionRunReserveSwapMissionUploadPolicy.validateDegradedHandoffPrerequisites(
            failureDisposition: .allowDegradedHandoffAfterOperatorConfirmation,
            operatorAttestation: ok
        )
        XCTAssertTrue(r3.isReady)
    }
}

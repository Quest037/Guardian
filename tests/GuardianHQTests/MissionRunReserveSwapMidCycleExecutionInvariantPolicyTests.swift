import XCTest
@testable import GuardianCore

final class MissionRunReserveSwapMidCycleExecutionInvariantPolicyTests: XCTestCase {

    func test_isLiveExecutingSession_true_whenRunningAndExecuting() {
        XCTAssertTrue(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.isLiveExecutingSession(
                status: .running,
                sessionPhase: .executing
            )
        )
    }

    func test_isLiveExecutingSession_true_whenPausedAndExecuting() {
        XCTAssertTrue(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.isLiveExecutingSession(
                status: .paused,
                sessionPhase: .executing
            )
        )
    }

    func test_isLiveExecutingSession_false_whenSetup() {
        XCTAssertFalse(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.isLiveExecutingSession(
                status: .setup,
                sessionPhase: .draft
            )
        )
    }

    func test_isLiveExecutingSession_false_whenRunningButStaging() {
        XCTAssertFalse(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.isLiveExecutingSession(
                status: .running,
                sessionPhase: .staging
            )
        )
    }

    func test_swapDoesNotResetTaskOrRunCycleCounters_isLockedTrue() {
        XCTAssertTrue(MissionRunReserveSwapMidCycleExecutionInvariantPolicy.swapDoesNotResetTaskOrRunCycleCounters)
    }

    func test_selectiveStaleTokenBatchCancellationRequiresExecutorWork_isLockedTrue() {
        XCTAssertTrue(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.selectiveStaleTokenBatchCancellationRequiresExecutorWork
        )
    }

    func test_pendingBatchesContainStaleVehicleToken_falseWhenNoCommandsForAssignment() {
        let batches: [MissionRunQueuedCommandBatch] = [
            MissionRunQueuedCommandBatch(
                tag: .complete,
                dispatch: .afterMissionCycle,
                commands: [
                    MissionRunIssuedCommand(
                        assignmentID: UUID(),
                        slotName: "P1",
                        vehicleTokenKey: "tok-a",
                        command: .arm,
                        issuer: .missionControl,
                        issuerKey: "test"
                    ),
                ]
            ),
        ]
        let aid = UUID()
        XCTAssertFalse(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.pendingBatchesContainStaleVehicleTokenForAssignment(
                batches: batches,
                assignmentID: aid,
                currentAssignmentFleetToken: "tok-b"
            )
        )
    }

    func test_pendingBatchesContainStaleVehicleToken_trueWhenTokenMismatchSameAssignment() {
        let aid = UUID()
        let batches: [MissionRunQueuedCommandBatch] = [
            MissionRunQueuedCommandBatch(
                tag: .complete,
                dispatch: .afterMissionCycle,
                commands: [
                    MissionRunIssuedCommand(
                        assignmentID: aid,
                        slotName: "P1",
                        vehicleTokenKey: "old-token",
                        command: .arm,
                        issuer: .missionControl,
                        issuerKey: "test"
                    ),
                ]
            ),
        ]
        XCTAssertTrue(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.pendingBatchesContainStaleVehicleTokenForAssignment(
                batches: batches,
                assignmentID: aid,
                currentAssignmentFleetToken: "new-token"
            )
        )
    }

    func test_pendingBatchesContainStaleVehicleToken_falseWhenTokenMatches() {
        let aid = UUID()
        let batches: [MissionRunQueuedCommandBatch] = [
            MissionRunQueuedCommandBatch(
                tag: .missionStart,
                dispatch: .immediate,
                commands: [
                    MissionRunIssuedCommand(
                        assignmentID: aid,
                        slotName: "P1",
                        vehicleTokenKey: "  same  ",
                        command: .arm,
                        issuer: .missionControl,
                        issuerKey: "test"
                    ),
                ]
            ),
        ]
        XCTAssertFalse(
            MissionRunReserveSwapMidCycleExecutionInvariantPolicy.pendingBatchesContainStaleVehicleTokenForAssignment(
                batches: batches,
                assignmentID: aid,
                currentAssignmentFleetToken: "same"
            )
        )
    }
}

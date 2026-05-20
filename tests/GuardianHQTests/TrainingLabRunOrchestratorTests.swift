import XCTest
@testable import GuardianCore

final class TrainingLabRunOrchestratorTests: XCTestCase {
    /// Regression: ``completeRun(terminalPhase:)`` must gate on the **session** phase (running/staged), not the terminal outcome (.failed / .succeeded).
    func test_sessionAllowsCompletion_whileIn_running_or_staged_only() {
        XCTAssertTrue(TrainingLabRunOrchestrator.sessionAllowsCompletion(whileIn: .running))
        XCTAssertTrue(TrainingLabRunOrchestrator.sessionAllowsCompletion(whileIn: .staged))
        XCTAssertFalse(TrainingLabRunOrchestrator.sessionAllowsCompletion(whileIn: .idle))
        XCTAssertFalse(TrainingLabRunOrchestrator.sessionAllowsCompletion(whileIn: .failed))
        XCTAssertFalse(TrainingLabRunOrchestrator.sessionAllowsCompletion(whileIn: .succeeded))
    }
}

import XCTest
@testable import GuardianHQ

@MainActor
final class FleetRecipeRunnerOperatorJoltTests: XCTestCase {

    func test_joltPendingWizardEscalationRetry_false_when_no_pending() {
        let runner = FleetRecipeRunner.shared
        XCTAssertFalse(runner.hasPendingWizardEscalation(forVehicleID: "vehicle-no-escalation"))
        XCTAssertFalse(runner.joltPendingWizardEscalationRetry(forVehicleID: "vehicle-no-escalation"))
    }
}

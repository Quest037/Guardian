import XCTest
@testable import GuardianCore

final class FleetNav2PlannerAvailabilityTests: XCTestCase {
    func test_plannerPlanningIsAvailable_false_when_setup_missing() {
        XCTAssertFalse(
            FleetNav2StackRunner.plannerPlanningIsAvailable(
                setupScriptPath: "/nonexistent/setup.bash"
            )
        )
    }
}

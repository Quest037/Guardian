import XCTest

@testable import GuardianCore

final class GuardianSquadAutonomyPlannerRoutingTests: XCTestCase {
    func test_summary_ugv_primary_nav2() {
        let summary = GuardianSquadAutonomyPlannerRouting.summary(
            primaryClass: .ugvWheeled,
            wingmanClasses: [.ugvTracked]
        )
        XCTAssertEqual(summary.primaryPlanner, .nav2)
        XCTAssertEqual(summary.wingmanPlanners, [.nav2])
        XCTAssertEqual(summary.logSummary, "nav2 + [nav2]")
    }

    func test_summary_mixed_uav_wingman_aerostack2() {
        let summary = GuardianSquadAutonomyPlannerRouting.summary(
            primaryClass: .ugvWheeled,
            wingmanClasses: [.uavCopter]
        )
        XCTAssertEqual(summary.primaryPlanner, .nav2)
        XCTAssertEqual(summary.wingmanPlanners, [.aerostack2])
        XCTAssertTrue(summary.logSummary.contains("aerostack2"))
    }
}

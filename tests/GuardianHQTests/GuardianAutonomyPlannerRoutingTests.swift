import XCTest
@testable import GuardianCore

final class GuardianAutonomyPlannerRoutingTests: XCTestCase {
    func test_ugv_defaults_to_nav2() {
        XCTAssertEqual(
            GuardianAutonomyPlannerRouting.defaultPlannerKind(for: .ugvWheeled),
            .nav2
        )
        XCTAssertEqual(
            GuardianAutonomyPlannerRouting.defaultPlannerKind(for: .ugvTracked),
            .nav2
        )
    }

    func test_uav_defaults_to_aerostack2() {
        XCTAssertEqual(
            GuardianAutonomyPlannerRouting.defaultPlannerKind(for: .uavCopter),
            .aerostack2
        )
        XCTAssertEqual(
            GuardianAutonomyPlannerRouting.defaultPlannerKind(for: .uavVTOL),
            .aerostack2
        )
    }

    func test_usv_nav2_uuv_none() {
        XCTAssertEqual(GuardianAutonomyPlannerRouting.defaultPlannerKind(for: .usv), .nav2)
        XCTAssertEqual(GuardianAutonomyPlannerRouting.defaultPlannerKind(for: .uuv), .none)
    }
}

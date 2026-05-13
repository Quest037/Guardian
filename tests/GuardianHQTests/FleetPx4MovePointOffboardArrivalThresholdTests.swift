import XCTest
@testable import GuardianHQ

/// Pins the horizontal-distance heuristic used by ``FleetLinkService`` for PX4 OFFBOARD move-point
/// (see ``FleetLinkService`` / `px4MovePointOffboardArrivalM` in source) to hub ↔ target haversine metres.
final class FleetPx4MovePointOffboardArrivalThresholdTests: XCTestCase {

    func test_haversine_within_four_metre_arrival_band() {
        let d = MissionRunMovePointParkPlanner.haversineMeters(
            lat1: 0,
            lon1: 0,
            lat2: 0.0000315,
            lon2: 0
        )
        XCTAssertLessThan(d, 4.0, "expected ~3.5 m north at equator to count as arrived")
    }

    func test_haversine_outside_four_metre_arrival_band() {
        let d = MissionRunMovePointParkPlanner.haversineMeters(
            lat1: 0,
            lon1: 0,
            lat2: 0.0001,
            lon2: 0
        )
        XCTAssertGreaterThan(d, 4.0, "expected ~11 m offset to still be navigating")
    }
}

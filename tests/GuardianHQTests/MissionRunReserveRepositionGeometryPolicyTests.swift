import XCTest

@testable import GuardianCore

final class MissionRunReserveRepositionGeometryPolicyTests: XCTestCase {

    func test_default_geometry_is_rally() {
        XCTAssertEqual(MissionRunReserveRepositionGeometryPolicy.defaultGeometryKind, .rallyToActiveHoldPoint)
    }

    func test_colocated_threshold_positive() {
        XCTAssertGreaterThan(MissionRunReserveRepositionGeometryPolicy.colocatedHorizontalThresholdMeters, 0)
    }

    func test_rally_and_replace_in_place_need_no_offset() {
        let r = MissionRunReserveRepositionGeometryPolicy.validateGeometryReadiness(kind: .rallyToActiveHoldPoint, formationOffset: nil)
        XCTAssertTrue(r.isReady)
        let p = MissionRunReserveRepositionGeometryPolicy.validateGeometryReadiness(kind: .replaceInPlaceIfColocated, formationOffset: nil)
        XCTAssertTrue(p.isReady)
    }

    func test_join_formation_requires_offset() {
        let bad = MissionRunReserveRepositionGeometryPolicy.validateGeometryReadiness(kind: .joinFormationOffset, formationOffset: nil)
        XCTAssertFalse(bad.isReady)
        let nan = MissionRunReserveRepositionGeometryPolicy.validateGeometryReadiness(
            kind: .joinFormationOffset,
            formationOffset: MissionRunReserveRepositionFormationOffset(eastMeters: .nan, northMeters: 0)
        )
        XCTAssertFalse(nan.isReady)
        let ok = MissionRunReserveRepositionGeometryPolicy.validateGeometryReadiness(
            kind: .joinFormationOffset,
            formationOffset: MissionRunReserveRepositionFormationOffset(eastMeters: 10, northMeters: -5)
        )
        XCTAssertTrue(ok.isReady)
    }
}

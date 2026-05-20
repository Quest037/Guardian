import XCTest
@testable import GuardianCore

/// Regression: pursuit must declare velocity-body when reverse / 3-point runs on PX4 UGV.
final class FormationFollowStreamPursuitModeTests: XCTestCase {

    func test_applyPlan_reverseOnUGV_usesVelocityBodyPursuit() {
        let context = GuardianMovementSlotApproachContext(
            vehicleType: .ugvWheeled,
            wingmanLatitudeDeg: -35,
            wingmanLongitudeDeg: 149,
            wingmanHeadingDeg: 0,
            slot: RouteCoordinate(lat: -35.002, lon: 149),
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM + 2,
            signedLateralErrorM: 0,
            distToSlotM: 8,
            primarySpeedMS: 1
        )
        let (plan, _) = GuardianMovementPlanner.planSlotApproach(context)
        XCTAssertEqual(plan.movementID, .reverse)
        let target = GuardianFormationSlotPursuitPlanning.applyPlan(
            coord: RouteCoordinate(lat: -35, lon: 149),
            targetHeadingDeg: 0,
            wingmanAbsoluteAltitudeM: 0,
            plan: plan
        )
        XCTAssertTrue(target.useVelocityBodyPursuit)
        XCTAssertNotNil(target.pursuitForwardMS)
        XCTAssertLessThan(target.pursuitForwardMS ?? 0, 0)
    }

    func test_applyPlan_forwardPursuitOnUGV_doesNotUseVelocityBody() {
        let context = GuardianMovementSlotApproachContext(
            vehicleType: .ugvWheeled,
            wingmanLatitudeDeg: -35,
            wingmanLongitudeDeg: 149,
            wingmanHeadingDeg: 0,
            slot: RouteCoordinate(lat: -35.002, lon: 149),
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: -3,
            signedLateralErrorM: 0,
            distToSlotM: 8,
            primarySpeedMS: 1
        )
        let (plan, _) = GuardianMovementPlanner.planSlotApproach(context)
        XCTAssertEqual(plan.movementID, .forwardPursuit)
        let target = GuardianFormationSlotPursuitPlanning.applyPlan(
            coord: RouteCoordinate(lat: -35, lon: 149),
            targetHeadingDeg: 0,
            wingmanAbsoluteAltitudeM: 0,
            plan: plan
        )
        XCTAssertFalse(target.useVelocityBodyPursuit)
    }
}

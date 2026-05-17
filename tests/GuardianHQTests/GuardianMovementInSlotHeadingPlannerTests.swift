import XCTest
@testable import GuardianHQ

@MainActor
final class GuardianMovementInSlotHeadingPlannerTests: XCTestCase {

    private func inSlotContext(
        headingDeg: Double,
        targetHeadingDeg: Double = 0,
        distM: Double = 0.5
    ) -> GuardianMovementSlotApproachContext {
        GuardianMovementSlotApproachContext(
            vehicleType: .ugvWheeled,
            wingmanLatitudeDeg: -35,
            wingmanLongitudeDeg: 149,
            wingmanHeadingDeg: headingDeg,
            slot: RouteCoordinate(lat: -35.00001, lon: 149.00001),
            convoyHeadingDeg: targetHeadingDeg,
            targetHeadingDeg: targetHeadingDeg,
            alongErrorM: 0.1,
            signedLateralErrorM: 0.05,
            distToSlotM: distM,
            primarySpeedMS: 0
        )
    }

    func test_positionLocked_requiredBeforeManeuver() {
        XCTAssertFalse(
            GuardianMovementInSlotHeadingPlanner.shouldStartHeadingManeuver(
                inSlotContext(headingDeg: 210, distM: 2.0)
            )
        )
        XCTAssertTrue(
            GuardianMovementInSlotHeadingPlanner.shouldStartHeadingManeuver(
                inSlotContext(headingDeg: 210, distM: 0.5)
            )
        )
    }

    func test_plan_startsWithPlottedRoute() {
        var state: GuardianMovementSlotSequenceState?
        let plan = GuardianMovementInSlotHeadingPlanner.plan(
            inSlotContext(headingDeg: 210),
            state: &state
        )
        XCTAssertEqual(plan?.movementID, .threePointReverse)
        XCTAssertLessThan(plan?.bodyForwardMS ?? 0, 0)
        XCTAssertNotNil(plan?.pursuitSetpoint)
        XCTAssertNotNil(state?.route)
        XCTAssertEqual(state?.phase, .reverseLeg)
    }

    func test_planner_usesForwardPursuitUntilPositionLocked() {
        let store = GuardianMovementSequenceStore()
        let context = inSlotContext(headingDeg: 220, distM: 3.0)
        let (plan, _) = GuardianMovementPlanner.planSlotApproach(
            context,
            vehicleID: "sysid:2",
            sequenceStore: store
        )
        XCTAssertEqual(plan.movementID, .forwardPursuit)
        XCTAssertNil(store.state(for: "sysid:2"))
    }

    func test_planner_selectsThreePoint_whenPositionLocked() {
        let store = GuardianMovementSequenceStore()
        let context = inSlotContext(headingDeg: 220, distM: 0.5)
        let (plan, _) = GuardianMovementPlanner.planSlotApproach(
            context,
            vehicleID: "sysid:2",
            sequenceStore: store
        )
        XCTAssertEqual(plan.movementID, .threePointReverse)
        XCTAssertNotNil(store.state(for: "sysid:2")?.route)
    }
}

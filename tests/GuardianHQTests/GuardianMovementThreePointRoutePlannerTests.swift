import XCTest
@testable import GuardianHQ

final class GuardianMovementThreePointRoutePlannerTests: XCTestCase {

    func test_build_producesReverseThenForwardWaypoints() {
        let slot = RouteCoordinate(lat: -35.00001, lon: 149.00001)
        let route = GuardianMovementThreePointRoutePlanner.build(
            slot: slot,
            startLatitudeDeg: -35,
            startLongitudeDeg: 149,
            startHeadingDeg: 220,
            targetHeadingDeg: 0
        )
        XCTAssertFalse(route.reverseWaypoints.isEmpty)
        XCTAssertFalse(route.forwardWaypoints.isEmpty)
        XCTAssertEqual(route.forwardWaypoints.last, slot)
    }

    func test_failedSequence_doesNotRestart_withoutClearingStore() {
        let store = GuardianMovementSequenceStore()
        var context = GuardianMovementSlotApproachContext(
            vehicleType: .ugvWheeled,
            wingmanLatitudeDeg: -35,
            wingmanLongitudeDeg: 149,
            wingmanHeadingDeg: 210,
            slot: RouteCoordinate(lat: -35.00001, lon: 149.00001),
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: 0.1,
            signedLateralErrorM: 0.05,
            distToSlotM: 0.5,
            primarySpeedMS: 0
        )
        var state: GuardianMovementSlotSequenceState?
        _ = GuardianMovementInSlotHeadingPlanner.plan(context, state: &state)
        XCTAssertEqual(state?.status, .running)
        state?.status = .failed
        state?.failureReason = "test"
        store.setState(state, for: "v1")
        context = GuardianMovementSlotApproachContext(
            vehicleType: context.vehicleType,
            wingmanLatitudeDeg: context.wingmanLatitudeDeg,
            wingmanLongitudeDeg: context.wingmanLongitudeDeg,
            wingmanHeadingDeg: 200,
            slot: context.slot,
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: 0.1,
            signedLateralErrorM: 0.05,
            distToSlotM: 0.5,
            primarySpeedMS: 0
        )
        var loaded = store.state(for: "v1")
        let plan = GuardianMovementInSlotHeadingPlanner.plan(context, state: &loaded)
        XCTAssertTrue(plan?.sequenceHalted == true)
        XCTAssertEqual(loaded?.status, .failed)
    }
}

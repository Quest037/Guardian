import XCTest
@testable import GuardianHQ

@MainActor
final class GuardianMovementPlannerTests: XCTestCase {

    private func sampleContext(
        along: Double,
        lateral: Double = 0,
        vehicleType: FleetVehicleType = .ugvWheeled
    ) -> GuardianMovementSlotApproachContext {
        GuardianMovementSlotApproachContext(
            vehicleType: vehicleType,
            wingmanLatitudeDeg: -35,
            wingmanLongitudeDeg: 149,
            wingmanHeadingDeg: 0,
            slot: RouteCoordinate(lat: -35.001, lon: 149),
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: along,
            signedLateralErrorM: lateral,
            distToSlotM: 5,
            primarySpeedMS: 1
        )
    }

    func test_planner_selectsReverse_whenAheadOfSlot() {
        let (plan, _) = GuardianMovementPlanner.planSlotApproach(
            sampleContext(along: MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM + 1)
        )
        XCTAssertEqual(plan.movementID, .reverse)
        XCTAssertLessThan(plan.bodyForwardMS, 0)
    }

    func test_planner_forward_whenBehindSlot() {
        let (plan, _) = GuardianMovementPlanner.planSlotApproach(sampleContext(along: -2))
        XCTAssertEqual(plan.movementID, .forwardPursuit)
        XCTAssertGreaterThan(plan.bodyForwardMS, 0)
    }

    func test_reverse_includesSteeringYaw_whenLateralOffset() {
        let plan = GuardianMovementPlanner.planSlotApproach(
            sampleContext(
                along: MissionSquadConvoyFollowControlPolicy.pursuitReverseAheadThresholdM + 2,
                lateral: 1.5
            )
        ).plan
        XCTAssertEqual(plan.movementID, .reverse)
        XCTAssertGreaterThan(abs(plan.yawspeedDegS), 0.5)
    }

    func test_evidence_recordsDeclinedStrafe_forUGV() {
        let evidence = GuardianMovementPlanner.evidence(
            from: sampleContext(along: 0, lateral: 3, vehicleType: .ugvWheeled)
        )
        XCTAssertTrue(evidence.declinedMovementIDs.contains(.strafe))
    }

    func test_forwardPursuit_zerosForwardInSlotWhenHeadingOff() {
        var ctx = sampleContext(along: 0.1, lateral: 0.1)
        ctx = GuardianMovementSlotApproachContext(
            vehicleType: ctx.vehicleType,
            wingmanLatitudeDeg: ctx.wingmanLatitudeDeg,
            wingmanLongitudeDeg: ctx.wingmanLongitudeDeg,
            wingmanHeadingDeg: 200,
            slot: ctx.slot,
            convoyHeadingDeg: 0,
            targetHeadingDeg: 0,
            alongErrorM: ctx.alongErrorM,
            signedLateralErrorM: ctx.signedLateralErrorM,
            distToSlotM: MissionSquadConvoyFollowControlPolicy.convoyAssemblyArrivalM,
            primarySpeedMS: ctx.primarySpeedMS
        )
        let plan = GuardianMovementPlanner.planSlotApproach(ctx).plan
        XCTAssertEqual(plan.bodyForwardMS, 0)
        XCTAssertGreaterThan(abs(plan.yawspeedDegS), 1)
    }
}

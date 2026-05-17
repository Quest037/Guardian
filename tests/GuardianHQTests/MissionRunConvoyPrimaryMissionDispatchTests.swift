import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunConvoyPrimaryMissionDispatchTests: XCTestCase {

    func test_guardianRouterFirstWaypointArrival_isSixMetres() {
        XCTAssertEqual(MissionSquadConvoyFollowControlPolicy.guardianRouterFirstWaypointArrivalM, 6.0)
    }

    func test_guardianRouterLaunchApproachArrived_usesRemainingAlongRouteOnly() {
        XCTAssertFalse(
            MissionSquadConvoyFollowControlPolicy.guardianRouterLaunchApproachArrived(
                remainingAlongRouteM: 100
            )
        )
        XCTAssertFalse(
            MissionSquadConvoyFollowControlPolicy.guardianRouterLaunchApproachArrived(
                remainingAlongRouteM: 6.01
            )
        )
        XCTAssertTrue(
            MissionSquadConvoyFollowControlPolicy.guardianRouterLaunchApproachArrived(
                remainingAlongRouteM: 6.0
            )
        )
        XCTAssertTrue(
            MissionSquadConvoyFollowControlPolicy.guardianRouterLaunchApproachArrived(
                remainingAlongRouteM: 2.0
            )
        )
    }

    /// Regression: crow-flies within 6 m must not complete the launch leg when path distance left is still large.
    func test_guardianRouterLaunchApproachArrived_ignoresCrowFliesProximity() {
        let arrivalM = MissionSquadConvoyFollowControlPolicy.guardianRouterFirstWaypointArrivalM
        let distToFirstWaypointM = arrivalM - 1.0
        let remainingAlongRouteM = 20_000.0
        XCTAssertLessThanOrEqual(distToFirstWaypointM, arrivalM)
        XCTAssertFalse(
            MissionSquadConvoyFollowControlPolicy.guardianRouterLaunchApproachArrived(
                remainingAlongRouteM: remainingAlongRouteM
            )
        )
    }

    func test_primaryConvoyStationaryMaxGroundSpeed_isLow() {
        XCTAssertEqual(MissionSquadConvoyFollowControlPolicy.primaryConvoyStationaryMaxGroundSpeedMS, 0.2)
    }

    func test_launchLegHoldPrimary_whenWingmenLag() {
        XCTAssertTrue(
            MissionSquadConvoyFollowControlPolicy.launchLegShouldHoldPrimaryInPlace(
                distToFirstWaypointM: 100,
                remainingAlongRouteM: 100,
                wingmenLagging: true
            )
        )
    }

    func test_launchLegHoldPrimary_nearFirstWaypoint_withoutWingmanLag() {
        XCTAssertTrue(
            MissionSquadConvoyFollowControlPolicy.launchLegShouldHoldPrimaryInPlace(
                distToFirstWaypointM: 10,
                remainingAlongRouteM: 100,
                wingmenLagging: false
            )
        )
        XCTAssertFalse(
            MissionSquadConvoyFollowControlPolicy.launchLegShouldHoldPrimaryInPlace(
                distToFirstWaypointM: 20,
                remainingAlongRouteM: 100,
                wingmenLagging: false
            )
        )
    }

    func test_startMissionAfterLaunchLeg_uses_continue_mission_recipe() {
        let assign = UUID()
        let issued = MissionRunConvoyPrimaryMissionDispatch.startMissionAfterLaunchLegCommand(
            primaryAssignmentID: assign,
            slotName: "Alpha",
            vehicleTokenKey: "token"
        )
        guard case .recipe(let name, _) = issued.dispatch else {
            return XCTFail("expected continue-mission recipe dispatch")
        }
        XCTAssertEqual(name, FleetMissionRecipeRegistrations.doContinueMissionAfterOperatorParkRecipeName)
    }
}

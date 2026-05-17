import XCTest
@testable import GuardianHQ

final class MissionControlSquadConvoyFormationUtilitiesTests: XCTestCase {

    func test_desiredCoordinate_firstWingman_isAsternOfPrimary() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
        let behind = MissionControlSquadConvoyFormationUtilities.desiredCoordinate(
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertLessThan(behind.lat, -35)
        XCTAssertEqual(behind.lon, 149, accuracy: 0.0001)
    }

    func test_desiredCoordinate_secondWingman_fartherAstern() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
        let w0 = MissionControlSquadConvoyFormationUtilities.desiredCoordinate(
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let w1 = MissionControlSquadConvoyFormationUtilities.desiredCoordinate(
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 1,
            spacing: spacing
        )
        XCTAssertLessThan(w1.lat, w0.lat)
    }

    func test_offsetCoordinate_headingEast_movesTargetEast() {
        let pt = MissionControlSquadConvoyFormationUtilities.offsetCoordinate(
            latitudeDeg: 0,
            longitudeDeg: 0,
            headingDeg: 90,
            forwardMeters: 10,
            rightMeters: 0
        )
        XCTAssertGreaterThan(pt.lon, 0)
        XCTAssertEqual(pt.lat, 0, accuracy: 0.00001)
    }

    func test_desiredCoordinateOnTaskPath_wingmanStaysOnNorthLeg() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
        let primaryLat = 50.7535
        let wingman = MissionControlSquadConvoyFormationUtilities.desiredCoordinateOnTaskPath(
            waypoints: task.waypoints,
            primaryLatitudeDeg: primaryLat,
            primaryLongitudeDeg: -1.6190,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertNotNil(wingman)
        XCTAssertLessThan(wingman!.lat, primaryLat)
        XCTAssertEqual(wingman!.lon, -1.6190, accuracy: 0.00005)
    }

    func test_desiredConvoySlot_headingAsternBeforeFirstWaypoint() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
        let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: 50.7532,
            primaryLongitudeDeg: -1.6100,
            primaryHeadingDeg: 90,
            primaryMissionProgressCurrent: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertFalse(slot.usesPathPolyline)
        let bodyOnly = MissionControlSquadConvoyFormationUtilities.desiredCoordinate(
            primaryLatitudeDeg: 50.7532,
            primaryLongitudeDeg: -1.6100,
            primaryHeadingDeg: 90,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertEqual(slot.coordinate.lat, bodyOnly.lat, accuracy: 0.000001)
        XCTAssertEqual(slot.coordinate.lon, bodyOnly.lon, accuracy: 0.000001)
    }

    func test_shouldAnchorConvoyToTaskPath_falseWhenPrimaryFarFromPolyline() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        XCTAssertFalse(
            MissionControlSquadConvoyFormationUtilities.shouldAnchorConvoyToTaskPath(
                task: task,
                primaryLatitudeDeg: 50.7535,
                primaryLongitudeDeg: -1.6100,
                primaryMissionProgressCurrent: 2,
                maxLateralM: 12
            )
        )
    }

    func test_shouldAnchorConvoyToTaskPath_trueWhenPastFirstWaypointOnPath() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        XCTAssertTrue(
            MissionControlSquadConvoyFormationUtilities.shouldAnchorConvoyToTaskPath(
                task: task,
                primaryLatitudeDeg: 50.7540,
                primaryLongitudeDeg: -1.6190,
                primaryMissionProgressCurrent: nil
            )
        )
    }

    func test_shouldAnchorConvoyToTaskPath_falseWhenPathAnchorDisallowed() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        XCTAssertFalse(
            MissionControlSquadConvoyFormationUtilities.shouldAnchorConvoyToTaskPath(
                task: task,
                primaryLatitudeDeg: 50.7539,
                primaryLongitudeDeg: -1.6190,
                primaryMissionProgressCurrent: 1,
                allowPathPolylineAnchor: false
            )
        )
    }

    func test_desiredConvoySlot_headingAsternWhenPathAnchorDisallowedNearWP1() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 3, lateralLaneMeters: 0)
        let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: 50.7539,
            primaryLongitudeDeg: -1.6190,
            primaryHeadingDeg: 90,
            primaryMissionProgressCurrent: 1,
            wingmanOrdinal: 0,
            spacing: spacing,
            allowPathPolylineAnchor: false
        )
        XCTAssertFalse(slot.usesPathPolyline)
        XCTAssertEqual(slot.convoyHeadingDeg, 90, accuracy: 0.001)
    }

    func test_shouldAnchorConvoyToTaskPathDuringMissionFollow_whenOnPolylineBeforeWP2() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        XCTAssertTrue(
            MissionControlSquadConvoyFormationUtilities.shouldAnchorConvoyToTaskPathDuringMissionFollow(
                task: task,
                primaryLatitudeDeg: 50.7532,
                primaryLongitudeDeg: -1.6190
            )
        )
        XCTAssertFalse(
            MissionControlSquadConvoyFormationUtilities.shouldAnchorConvoyToTaskPath(
                task: task,
                primaryLatitudeDeg: 50.7532,
                primaryLongitudeDeg: -1.6190,
                primaryMissionProgressCurrent: 0
            )
        )
    }

    func test_desiredConvoySlotOnLaunchApproachRoute_wingmanAsternOnGRSpine() {
        let route = [
            RouteCoordinate(lat: 50.7530, lon: -1.6190),
            RouteCoordinate(lat: 50.7540, lon: -1.6190),
        ]
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 3, lateralLaneMeters: 0)
        let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlotOnLaunchApproachRoute(
            route: route,
            primaryLatitudeDeg: 50.7535,
            primaryLongitudeDeg: -1.6190,
            primaryHeadingDeg: 45,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertNotNil(slot)
        XCTAssertTrue(slot!.usesPathPolyline)
        XCTAssertLessThan(slot!.coordinate.lat, 50.7535)
        XCTAssertEqual(slot!.coordinate.lon, -1.6190, accuracy: 0.00005)
    }

    func test_desiredConvoySlot_onPathDuringMissionFollow_beforePastFirstWaypoint() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 3, lateralLaneMeters: 0)
        let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: 50.7532,
            primaryLongitudeDeg: -1.6190,
            primaryHeadingDeg: 90,
            primaryMissionProgressCurrent: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertTrue(slot.usesPathPolyline)
        XCTAssertEqual(slot.coordinate.lon, -1.6190, accuracy: 0.00005)
    }

    func test_desiredConvoySlot_onPathAfterFirstWaypoint() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 3, lateralLaneMeters: 0)
        let slot = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: 50.7539,
            primaryLongitudeDeg: -1.6190,
            primaryHeadingDeg: 45,
            primaryMissionProgressCurrent: 1,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertTrue(slot.usesPathPolyline)
        XCTAssertEqual(slot.coordinate.lon, -1.6190, accuracy: 0.00005)
        XCTAssertLessThan(slot.coordinate.lat, 50.7539)
    }

    func test_desiredConvoySlot_firstWingmanThreeMetresBehindOnPath() {
        let task = MissionTask(
            name: "T",
            waypoints: [
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7530, lon: -1.6190)),
                RouteWaypoint(coord: RouteCoordinate(lat: 50.7540, lon: -1.6190)),
            ]
        )
        let spacing = MissionSquadConvoySpacing.ugvConvoyTest
        let primaryLat = 50.7539
        let w0 = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: primaryLat,
            primaryLongitudeDeg: -1.6190,
            primaryHeadingDeg: 0,
            primaryMissionProgressCurrent: 1,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let w1 = MissionControlSquadConvoyFormationUtilities.desiredConvoySlot(
            task: task,
            primaryLatitudeDeg: primaryLat,
            primaryLongitudeDeg: -1.6190,
            primaryHeadingDeg: 0,
            primaryMissionProgressCurrent: 1,
            wingmanOrdinal: 1,
            spacing: spacing
        )
        let gap01 = MissionTelemetryGeo.horizontalDistanceM(
            lat1: w0.coordinate.lat, lon1: w0.coordinate.lon,
            lat2: w1.coordinate.lat, lon2: w1.coordinate.lon
        )
        XCTAssertEqual(gap01, 3, accuracy: 0.75)
    }

    func test_pursuitForwardSpeed_boostsWhenBehindSlot() {
        let speed = MissionControlSquadConvoyFormationUtilities.pursuitForwardSpeedMS(
            alongErrorM: -6,
            distToSlotM: 8,
            primarySpeedMS: 2
        )
        XCTAssertGreaterThan(speed, 2)
    }

    func test_pursuitForwardSpeed_slowsWhenAheadOfSlot() {
        let speed = MissionControlSquadConvoyFormationUtilities.pursuitForwardSpeedMS(
            alongErrorM: 4,
            distToSlotM: 4,
            primarySpeedMS: 2
        )
        XCTAssertLessThan(speed, 2)
    }

    func test_convoyAlongTrackError_signAheadVsBehind() {
        let slot = RouteCoordinate(lat: 50.7535, lon: -1.6190)
        let ahead = MissionControlSquadConvoyFormationUtilities.convoyAlongTrackErrorM(
            wingmanLatitudeDeg: 50.7538,
            wingmanLongitudeDeg: -1.6190,
            slotCoordinate: slot,
            convoyHeadingDeg: 0
        )
        let behind = MissionControlSquadConvoyFormationUtilities.convoyAlongTrackErrorM(
            wingmanLatitudeDeg: 50.7532,
            wingmanLongitudeDeg: -1.6190,
            slotCoordinate: slot,
            convoyHeadingDeg: 0
        )
        XCTAssertGreaterThan(ahead, 0)
        XCTAssertLessThan(behind, 0)
    }

    func test_streamedConvoySetpoint_usesExtendedLeashWhenBehind() {
        let slot = RouteCoordinate(lat: 50.7540, lon: -1.6190)
        let setpoint = MissionControlSquadConvoyFormationUtilities.streamedConvoySetpointCoordinate(
            wingmanLatitudeDeg: 50.7530,
            wingmanLongitudeDeg: -1.6190,
            slotCoordinate: slot,
            convoyHeadingDeg: 0,
            alongErrorM: -12
        )
        XCTAssertGreaterThan(setpoint.lat, 50.7530)
        XCTAssertLessThan(setpoint.lat, slot.lat)
    }

    func test_streamedConvoySetpoint_leashInMidRange() {
        let slot = RouteCoordinate(lat: 50.75342, lon: -1.6190)
        let setpoint = MissionControlSquadConvoyFormationUtilities.streamedConvoySetpointCoordinate(
            wingmanLatitudeDeg: 50.75340,
            wingmanLongitudeDeg: -1.6190,
            slotCoordinate: slot,
            convoyHeadingDeg: 0,
            alongErrorM: 0.5,
            snapWithinM: 1.25,
            directSlotBeyondM: 3.0,
            leashMinM: 2.5,
            leashMaxM: 6.0
        )
        XCTAssertGreaterThan(setpoint.lat, 50.75340)
        XCTAssertLessThan(setpoint.lat, slot.lat)
    }

    func test_streamedConvoySetpoint_snapsToSlotWhenClose() {
        let slot = RouteCoordinate(lat: 50.75350, lon: -1.6190)
        let snapped = MissionControlSquadConvoyFormationUtilities.streamedConvoySetpointCoordinate(
            wingmanLatitudeDeg: 50.753499,
            wingmanLongitudeDeg: -1.6190,
            slotCoordinate: slot,
            convoyHeadingDeg: 0,
            snapWithinM: 1.25
        )
        XCTAssertEqual(snapped.lat, slot.lat, accuracy: 0.000001)
        XCTAssertEqual(snapped.lon, slot.lon, accuracy: 0.000001)
    }
}

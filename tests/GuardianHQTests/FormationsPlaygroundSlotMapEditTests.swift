import XCTest
@testable import GuardianHQ

@MainActor
final class FormationsPlaygroundSlotMapEditTests: XCTestCase {
    func test_slotCloneMarkerID_isDistinctFromLiveSlot() {
        XCTAssertNotEqual(
            MapVehicleMarkerIdentity.formationPlaygroundSlotTarget(ordinal: 0),
            MapVehicleMarkerIdentity.formationPlaygroundSlotClone(ordinal: 0)
        )
    }

    func test_formationSlotGroupMapEdit_equatable() {
        let a = GuardianFormationSlotGroupMapEdit(
            centerLat: 50,
            centerLon: -1,
            headingDeg: 0,
            circleRadiusM: 8
        )
        XCTAssertEqual(a, a)
    }

    func test_slotGroupRotateHandle_onCircleAtHeading() {
        let centerLat = 50.0
        let centerLon = -1.0
        let radiusM = 8.0
        let handle = MissionSquadFormationGeometry.offsetCoordinate(
            latitudeDeg: centerLat,
            longitudeDeg: centerLon,
            headingDeg: 90,
            forwardMeters: radiusM,
            rightMeters: 0
        )
        let heading = MissionTelemetryGeo.bearingDegrees(
            lat1: centerLat,
            lon1: centerLon,
            lat2: handle.lat,
            lon2: handle.lon
        )
        XCTAssertEqual(heading, 90, accuracy: 5)
    }

    func test_wingmanSlotPosition_movesWhenFormationHeadingChanges() {
        let primaryLat = 50.0
        let primaryLon = -1.0
        let spacing = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: .ugvWheeled,
            shape: .tight,
            formation: .arrowhead
        )
        let atNorth = Utilities.mission.squadFormation.desiredPadSlot(
            formation: .arrowhead,
            primaryLatitudeDeg: primaryLat,
            primaryLongitudeDeg: primaryLon,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let atEast = Utilities.mission.squadFormation.desiredPadSlot(
            formation: .arrowhead,
            primaryLatitudeDeg: primaryLat,
            primaryLongitudeDeg: primaryLon,
            primaryHeadingDeg: 90,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let deltaM = MissionRunMovePointParkPlanner.haversineMeters(
            lat1: atNorth.lat,
            lon1: atNorth.lon,
            lat2: atEast.lat,
            lon2: atEast.lon
        )
        XCTAssertGreaterThan(deltaM, 0.5)
    }
}

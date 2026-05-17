import XCTest
@testable import GuardianHQ

@MainActor
final class MissionSquadFormationGeometryTests: XCTestCase {

    func test_convoy_wingmen_collinear_astern() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 8)
        let w0 = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .convoy,
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let w1 = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .convoy,
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 1,
            spacing: spacing
        )
        XCTAssertEqual(w0.lon, 149, accuracy: 0.0001)
        XCTAssertEqual(w1.lon, 149, accuracy: 0.0001)
        XCTAssertLessThan(w0.lat, -35)
        XCTAssertLessThan(w1.lat, w0.lat)
    }

    func test_staggeredConvoy_alternates_lateral() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 6)
        let left = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .staggeredConvoy,
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let right = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .staggeredConvoy,
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 1,
            spacing: spacing
        )
        XCTAssertGreaterThan(left.lon, 149)
        XCTAssertLessThan(right.lon, 149)
        XCTAssertLessThan(left.lat, -35)
        XCTAssertLessThan(right.lat, left.lat)
    }

    func test_arrowhead_row1_never_centeredOnPrimaryLongitude() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
        for ordinal in 0..<2 {
            let slot = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
                formation: .arrowhead,
                primaryLatitudeDeg: -35,
                primaryLongitudeDeg: 149,
                primaryHeadingDeg: 0,
                wingmanOrdinal: ordinal,
                spacing: spacing
            )
            XCTAssertNotEqual(slot.lon, 149, accuracy: 0.0001)
        }
    }

    func test_chevron_row1_widerThanDeep() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 20, lateralLaneMeters: 0)
        let left = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .chevron,
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let right = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .chevron,
            primaryLatitudeDeg: -35,
            primaryLongitudeDeg: 149,
            primaryHeadingDeg: 0,
            wingmanOrdinal: 1,
            spacing: spacing
        )
        let depthM = abs(left.lat - (-35)) * 111_320
        let widthM = abs(right.lon - left.lon) * 85_000
        XCTAssertGreaterThan(widthM, depthM)
        XCTAssertGreaterThan(widthM, 24)
        XCTAssertLessThan(depthM, 14)
    }

    func test_utilitiesMissionNamespace_matchesGeometryPadSlot() {
        let spacing = MissionSquadConvoySpacing(alongTrackMetersPerOrdinal: 12, lateralLaneMeters: 4)
        let viaUtilities = Utilities.mission.squadFormation.desiredPadSlot(
            formation: .staggeredConvoy,
            primaryLatitudeDeg: 10,
            primaryLongitudeDeg: 20,
            primaryHeadingDeg: 45,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        let direct = MissionSquadFormationGeometry.desiredPadSlotCoordinate(
            formation: .staggeredConvoy,
            primaryLatitudeDeg: 10,
            primaryLongitudeDeg: 20,
            primaryHeadingDeg: 45,
            wingmanOrdinal: 0,
            spacing: spacing
        )
        XCTAssertEqual(viaUtilities.lat, direct.lat, accuracy: 0.0000001)
        XCTAssertEqual(viaUtilities.lon, direct.lon, accuracy: 0.0000001)
    }
}

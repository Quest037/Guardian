import XCTest
@testable import GuardianCore

final class MissionSquadFormationFootprintSpacingTests: XCTestCase {

    func test_ugv_medium_tight_convoy_along_exceeds_sim_three_metre_baseline() {
        let tight = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: .ugvWheeled,
            spacing: .tight,
            formation: .convoy,
            rosterEntries: [(.ugvWheeled, .medium)]
        )
        XCTAssertGreaterThan(tight.alongTrackMetersPerOrdinal, 3)
        let minAlong = MissionSquadFormationFootprintSpacing.minimumAlongOrdinalM(
            footprints: [MissionSquadFormationFootprintSpacing.footprintMetres(
                vehicleClass: .ugvWheeled,
                tier: .medium
            )],
            universalClass: .ugv
        )
        XCTAssertGreaterThanOrEqual(tight.alongTrackMetersPerOrdinal, minAlong)
    }

    func test_mixed_tier_squad_raises_floor_above_medium_only() {
        let mediumOnly = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: .ugvWheeled,
            spacing: .tight,
            formation: .staggeredConvoy,
            rosterEntries: [(.ugvWheeled, .medium)]
        )
        let withLargeWingman = MissionSquadConvoySpacingPolicy.resolvedSpacing(
            taskPattern: .convoy,
            primaryGranularClass: .ugvWheeled,
            spacing: .tight,
            formation: .staggeredConvoy,
            rosterEntries: [
                (.ugvWheeled, .medium),
                (.ugvWheeled, .large),
            ]
        )
        XCTAssertGreaterThan(
            withLargeWingman.lateralLaneMeters,
            mediumOnly.lateralLaneMeters
        )
    }
}

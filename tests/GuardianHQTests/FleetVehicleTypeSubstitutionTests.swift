import XCTest
@testable import GuardianCore

final class FleetVehicleTypeSubstitutionTests: XCTestCase {
    func test_exactGranularType_equalKinds() {
        for t in FleetVehicleType.allCases {
            XCTAssertTrue(FleetVehicleType.substitutionMatches(required: t, candidate: t, policy: .exactGranularType))
        }
    }

    func test_exactGranularType_inequality() {
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .uavCopter,
                candidate: .uavFixedWing,
                policy: .exactGranularType
            )
        )
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .ugvWheeled,
                candidate: .ugvTracked,
                policy: .exactGranularType
            )
        )
    }

    func test_exactGranularType_unknown_only_matches_unknown() {
        XCTAssertTrue(
            FleetVehicleType.substitutionMatches(required: .unknown, candidate: .unknown, policy: .exactGranularType)
        )
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(required: .unknown, candidate: .uavCopter, policy: .exactGranularType)
        )
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(required: .uavCopter, candidate: .unknown, policy: .exactGranularType)
        )
    }

    func test_missionRunReserveSwap_ugv_wheeled_tracked_interchange() {
        XCTAssertTrue(
            FleetVehicleType.substitutionMatches(
                required: .ugvWheeled,
                candidate: .ugvTracked,
                policy: .missionRunReserveSwap
            )
        )
        XCTAssertTrue(
            FleetVehicleType.substitutionMatches(
                required: .ugvTracked,
                candidate: .ugvWheeled,
                policy: .missionRunReserveSwap
            )
        )
    }

    func test_missionRunReserveSwap_uav_not_interchangeable() {
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .uavCopter,
                candidate: .uavFixedWing,
                policy: .missionRunReserveSwap
            )
        )
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .uavCopter,
                candidate: .uavVTOL,
                policy: .missionRunReserveSwap
            )
        )
    }

    func test_missionRunReserveSwap_ugv_legged_exact_only() {
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .ugvLegged,
                candidate: .ugvWheeled,
                policy: .missionRunReserveSwap
            )
        )
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .ugvLegged,
                candidate: .ugvTracked,
                policy: .missionRunReserveSwap
            )
        )
    }

    func test_missionRunReserveSwap_marine_exact_only() {
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(required: .usv, candidate: .uuv, policy: .missionRunReserveSwap)
        )
    }

    func test_missionRunReserveSwap_unknown_rejected_against_typed() {
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .unknown,
                candidate: .uavCopter,
                policy: .missionRunReserveSwap
            )
        )
        XCTAssertFalse(
            FleetVehicleType.substitutionMatches(
                required: .uavCopter,
                candidate: .unknown,
                policy: .missionRunReserveSwap
            )
        )
    }

    func test_instance_convenience_matches_static() {
        let required = FleetVehicleType.ugvTracked
        let candidate = FleetVehicleType.ugvWheeled
        XCTAssertEqual(
            required.substitutionMatches(candidate: candidate, policy: .missionRunReserveSwap),
            FleetVehicleType.substitutionMatches(required: required, candidate: candidate, policy: .missionRunReserveSwap)
        )
    }
}

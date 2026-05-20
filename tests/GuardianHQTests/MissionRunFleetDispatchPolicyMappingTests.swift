import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunFleetDispatchPolicyMappingTests: XCTestCase {

    func test_abort_returnToLaunch_isReturnHomeRecipe() {
        guard let d = MissionRunFleetDispatch.preferentialAbortTacticDispatch(.returnToLaunch) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .recipe(let name, let params) = d else {
            XCTFail("expected recipe, got \(d)")
            return
        }
        XCTAssertEqual(name, FleetMissionRecipeRegistrations.doReturnHomeRecipeName)
        XCTAssertEqual(params, .empty)
    }

    func test_abort_loiter_isCatalogueLoiter() {
        guard let d = MissionRunFleetDispatch.preferentialAbortTacticDispatch(.loiter) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue, got \(d)")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoLoiter)
        XCTAssertEqual(params, .empty)
    }

    func test_abort_park_isCataloguePark() {
        guard let d = MissionRunFleetDispatch.preferentialAbortTacticDispatch(.park) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue, got \(d)")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoPark)
        XCTAssertEqual(params, .empty)
    }

    func test_abort_nearestOpenMapPoint_nil() {
        XCTAssertNil(MissionRunFleetDispatch.preferentialAbortTacticDispatch(.nearestOpenMapPoint))
    }

    func test_complete_none_nil() {
        XCTAssertNil(MissionRunFleetDispatch.preferentialCompleteTacticDispatch(.none))
    }

    func test_betweenCycles_rtl_isReturnHomeRecipe() {
        guard let d = MissionRunFleetDispatch.betweenCyclesTaskDispatch(.returnToLaunch) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .recipe(let name, let params) = d else {
            XCTFail("expected recipe, got \(d)")
            return
        }
        XCTAssertEqual(name, FleetMissionRecipeRegistrations.doReturnHomeRecipeName)
        XCTAssertEqual(params, .empty)
    }

    func test_betweenCycles_loiter_isCatalogueLoiter() {
        guard let d = MissionRunFleetDispatch.betweenCyclesTaskDispatch(.holdPosition) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue, got \(d)")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoLoiter)
        XCTAssertEqual(params, .empty)
    }

    func test_betweenCycles_park_isCataloguePark() {
        guard let d = MissionRunFleetDispatch.betweenCyclesTaskDispatch(.park) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue, got \(d)")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoPark)
        XCTAssertEqual(params, .empty)
    }

    func test_betweenCycles_failureFallback_uavKinds_areLoiter() {
        for v in [FleetVehicleType.uavCopter, .uavFixedWing, .uavVTOL] {
            let d = MissionRunFleetDispatch.betweenCyclesFailureFallbackDispatch(expectedGranularClass: v)
            guard case .catalogue(let name, let params) = d else {
                XCTFail("expected catalogue for \(v), got \(d)")
                return
            }
            XCTAssertEqual(name, .fleetVehicleDoLoiter)
            XCTAssertEqual(params, .empty)
        }
    }

    func test_betweenCycles_failureFallback_nonUavKinds_arePark() {
        for v in [FleetVehicleType.ugvWheeled, .ugvTracked, .ugvLegged, .usv, .uuv, .unknown] {
            let d = MissionRunFleetDispatch.betweenCyclesFailureFallbackDispatch(expectedGranularClass: v)
            guard case .catalogue(let name, let params) = d else {
                XCTFail("expected catalogue for \(v), got \(d)")
                return
            }
            XCTAssertEqual(name, .fleetVehicleDoPark)
            XCTAssertEqual(params, .empty)
        }
    }
}

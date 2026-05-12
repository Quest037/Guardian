import XCTest
@testable import GuardianHQ

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

    func test_betweenCycles_land_isCatalogueLand() {
        guard let d = MissionRunFleetDispatch.betweenCyclesTaskDispatch(.land) else {
            XCTFail("expected dispatch")
            return
        }
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue, got \(d)")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoLand)
        XCTAssertEqual(params, .empty)
    }
}

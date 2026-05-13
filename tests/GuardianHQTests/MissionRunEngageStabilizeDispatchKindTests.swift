import XCTest

@testable import GuardianHQ

final class MissionRunEngageStabilizeDispatchKindTests: XCTestCase {

    func test_park_maps_to_catalogue_park() {
        let d = MissionRunEngageStabilizeDispatchKind.park.missionRunFleetDispatch
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue dispatch")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoPark)
        XCTAssertEqual(params, .empty)
    }

    func test_loiter_maps_to_catalogue_loiter() {
        let d = MissionRunEngageStabilizeDispatchKind.loiter.missionRunFleetDispatch
        guard case .catalogue(let name, let params) = d else {
            XCTFail("expected catalogue dispatch")
            return
        }
        XCTAssertEqual(name, .fleetVehicleDoLoiter)
        XCTAssertEqual(params, .empty)
    }

    func test_operator_short_labels() {
        XCTAssertEqual(MissionRunEngageStabilizeDispatchKind.park.operatorShortLabel, "Park")
        XCTAssertEqual(MissionRunEngageStabilizeDispatchKind.loiter.operatorShortLabel, "Loiter")
    }
}

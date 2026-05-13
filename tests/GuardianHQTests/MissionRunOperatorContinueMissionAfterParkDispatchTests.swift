import XCTest
@testable import GuardianHQ

final class MissionRunOperatorContinueMissionAfterParkDispatchTests: XCTestCase {

    func test_dispatch_recipe_name_matches_registration() {
        let k = MissionRunOperatorContinueMissionAfterParkDispatchKind.armModeMissionStart
        guard case .recipe(let name, let params) = k.missionRunFleetDispatch else {
            return XCTFail("Expected recipe dispatch")
        }
        XCTAssertTrue(params.values.isEmpty)
        XCTAssertEqual(name.rawValue, FleetMissionRecipeRegistrations.doContinueMissionAfterOperatorParkRecipeName.rawValue)
    }
}

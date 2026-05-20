import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunConvoyLaunchPipelineTests: XCTestCase {

    func test_startMissionAfterLaunchLeg_doesNotUseUploadRecipe() {
        let issued = MissionRunConvoyPrimaryMissionDispatch.startMissionAfterLaunchLegCommand(
            primaryAssignmentID: UUID(),
            slotName: "Alpha",
            vehicleTokenKey: "token"
        )
        guard case .recipe(let name, _) = issued.dispatch else {
            return XCTFail("expected continue-mission recipe")
        }
        XCTAssertEqual(name, FleetMissionRecipeRegistrations.doContinueMissionAfterOperatorParkRecipeName)
        XCTAssertNotEqual(name.rawValue, FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName.rawValue)
    }
}

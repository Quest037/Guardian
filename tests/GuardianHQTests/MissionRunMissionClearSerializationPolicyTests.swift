import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunMissionClearSerializationPolicyTests: XCTestCase {
    func test_commandsContainCatalogueMissionClear_trueForMissionClearCatalogue() {
        let cmd = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "Alpha",
            vehicleTokenKey: "token",
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertTrue(MissionRunExecutionSubsystem.commandsContainCatalogueMissionClear([cmd]))
    }

    func test_commandsContainCatalogueMissionClear_falseForOtherCatalogue() {
        let cmd = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "Alpha",
            vehicleTokenKey: "token",
            dispatch: .catalogue(name: .fleetVehicleDoLand, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertFalse(MissionRunExecutionSubsystem.commandsContainCatalogueMissionClear([cmd]))
    }

    func test_commandsContainCatalogueMissionClear_trueWhenMixedWithTrailingRecipe() {
        let clear = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "Alpha",
            vehicleTokenKey: "token",
            dispatch: .catalogue(name: .fleetVehicleDoMissionClear, parameters: .empty),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        let recipe = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "Alpha",
            vehicleTokenKey: "token",
            dispatch: .recipe(
                name: FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
                parameters: .empty
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.plannerAbort
        )
        XCTAssertTrue(MissionRunExecutionSubsystem.commandsContainCatalogueMissionClear([clear, recipe]))
    }
}

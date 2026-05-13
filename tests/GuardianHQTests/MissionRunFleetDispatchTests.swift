import XCTest
@testable import GuardianHQ

/// ``MissionRunFleetDispatch`` + ``MissionRunIssuedCommand`` wiring for MRE fleet dispatch (catalogue + recipe).
final class MissionRunFleetDispatchTests: XCTestCase {

    func test_issued_command_convenience_init_wraps_vehicle_command() {
        let cmd = MissionRunIssuedCommand(
            assignmentID: UUID(),
            slotName: "Alpha",
            vehicleTokenKey: "token",
            command: .arm,
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        guard case .vehicleCommand(let inner) = cmd.dispatch else {
            return XCTFail("expected vehicleCommand dispatch")
        }
        guard case .arm = inner else {
            return XCTFail("expected .arm")
        }
    }

    func test_reattribute_preserves_catalogue_dispatch() {
        let id = UUID()
        let assign = UUID()
        let params = FleetCommandParameters(values: ["missionItemsJSON": .string("[]")])
        let original = MissionRunIssuedCommand(
            id: id,
            assignmentID: assign,
            slotName: "Bravo",
            vehicleTokenKey: "token",
            dispatch: .catalogue(name: .fleetVehicleDoMissionUploadStart, parameters: params),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        let rewritten = original.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator)
        XCTAssertEqual(rewritten.dispatch, original.dispatch)
        XCTAssertEqual(rewritten.issuer, .operator)
        XCTAssertEqual(rewritten.issuerKey, MissionRunCommandIssuerKey.localOperator)
    }

    func test_reattribute_preserves_recipe_dispatch() {
        let id = UUID()
        let assign = UUID()
        let params = FleetRecipeParameters(values: [
            "missionItemsJSON": .string("[]"),
            "geofencePolygonsJSON": .string("[]"),
        ])
        let original = MissionRunIssuedCommand(
            id: id,
            assignmentID: assign,
            slotName: "Charlie",
            vehicleTokenKey: "token",
            dispatch: .recipe(
                name: FleetRecipeName.literal("recipe.fleet.do.mission.upload.start"),
                parameters: params
            ),
            issuer: .missionControl,
            issuerKey: MissionRunCommandIssuerKey.missionExecute
        )
        let rewritten = original.reattributed(issuer: .operator, issuerKey: MissionRunCommandIssuerKey.localOperator)
        XCTAssertEqual(rewritten.dispatch, original.dispatch)
        XCTAssertEqual(rewritten.issuer, .operator)
        XCTAssertEqual(rewritten.issuerKey, MissionRunCommandIssuerKey.localOperator)
    }
}

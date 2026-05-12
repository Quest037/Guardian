import XCTest
@testable import GuardianHQ

@MainActor
final class FleetMovePointParkRecipeTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        FleetRecipesCatalogueBootstrap.ensureRegistered()
        FleetMovePointParkRecipeRegistrations.registerAll()
    }

    func test_descriptorRegistered_movePointPark() {
        let name = FleetMovePointParkRecipeRegistrations.movePointParkRecipeName
        let d = FleetRecipesCatalogue.shared.descriptor(for: name)
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.riskTier, .confirmInLiveMission)
        XCTAssertTrue(d?.parameters.contains(where: { $0.name == "procedureLogSummary" }) ?? false)
    }

    func test_descriptor_containsArmProbeChildForCompositionRule() {
        let name = FleetMovePointParkRecipeRegistrations.movePointParkRecipeName
        guard let d = FleetRecipesCatalogue.shared.descriptor(for: name) else {
            XCTFail("missing descriptor")
            return
        }
        XCTAssertTrue(d.isComposite)
        XCTAssertEqual(
            d.containsRecipes,
            [FleetRecipeName.literal("recipe.fleet.diagnose.armprobe")]
        )
    }

    func test_bodyStepStructure_matchesMissionBodiesContract() {
        let name = FleetMovePointParkRecipeRegistrations.movePointParkRecipeName
        guard let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name) else {
            XCTFail("missing descriptor")
            return
        }
        guard let body = descriptor.body else {
            XCTFail("missing recipe body on descriptor")
            return
        }
        XCTAssertEqual(body.entryStepID.rawValue, "armProbe")
        XCTAssertEqual(body.overallBudgetSeconds, 600)
        XCTAssertEqual(body.steps.count, 4)
        XCTAssertEqual(body.steps.map(\.id.rawValue), ["armProbe", "reArm", "move", "park"])

        guard case .invokeRecipe(_, let probeRecipe, let probeParams, _) = body.steps[0] else {
            XCTFail("expected armProbe invokeRecipe")
            return
        }
        XCTAssertEqual(probeRecipe.rawValue, "recipe.fleet.diagnose.armprobe")
        XCTAssertTrue(probeParams.values.isEmpty)

        guard case .invokeCommand(_, let armCmd, let armParams, let armRetry, _) = body.steps[1] else {
            XCTFail("expected reArm invokeCommand")
            return
        }
        XCTAssertEqual(armCmd, FleetCommandName.fleetVehicleDoArm)
        XCTAssertTrue(armParams.values.isEmpty)
        XCTAssertEqual(armRetry?.maxAttempts, 3)

        guard case .invokeCommand(_, let moveCmd, let moveParams, let moveRetry, _) = body.steps[2] else {
            XCTFail("expected move invokeCommand")
            return
        }
        XCTAssertEqual(moveCmd, FleetCommandName.fleetVehicleDoMovePoint)
        XCTAssertEqual(moveRetry?.maxAttempts, 3)
        XCTAssertEqual(moveParams.value(named: "pointKind"), FleetRecipeParameterValue.reference(name: "pointKind"))
        XCTAssertEqual(moveParams.value(named: "latitudeDeg"), FleetRecipeParameterValue.reference(name: "latitudeDeg"))
        XCTAssertEqual(moveParams.value(named: "longitudeDeg"), FleetRecipeParameterValue.reference(name: "longitudeDeg"))
        XCTAssertEqual(moveParams.value(named: "relativeAltitudeM"), FleetRecipeParameterValue.reference(name: "relativeAltitudeM"))
        XCTAssertEqual(moveParams.value(named: "yawDeg"), FleetRecipeParameterValue.reference(name: "yawDeg"))

        guard case .invokeCommand(_, let parkCmd, let parkParams, let parkRetry, _) = body.steps[3] else {
            XCTFail("expected park invokeCommand")
            return
        }
        XCTAssertEqual(parkCmd, FleetCommandName.fleetVehicleDoPark)
        XCTAssertTrue(parkParams.values.isEmpty)
        XCTAssertEqual(parkRetry?.maxAttempts, 2)
    }

    func test_bodyValidatesAgainstCatalogue() {
        let name = FleetMovePointParkRecipeRegistrations.movePointParkRecipeName
        guard let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name) else {
            XCTFail("missing descriptor")
            return
        }
        guard let body = descriptor.body else {
            XCTFail("missing recipe body on descriptor")
            return
        }
        let errors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(errors.isEmpty, "move+park body should validate: \(errors)")
    }
}

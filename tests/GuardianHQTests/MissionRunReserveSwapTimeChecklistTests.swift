import XCTest

@testable import GuardianCore

@MainActor
final class MissionRunReserveSwapTimeChecklistTests: XCTestCase {

    override func setUp() {
        super.setUp()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap.ensureRegistered()
    }

    func test_arm_probe_recipes_registered() {
        let cat = FleetRecipesCatalogue.shared
        for name in MissionRunReserveSwapTimeChecklist.armProbeRecipeChoices() {
            XCTAssertNotNil(
                cat.descriptor(for: name),
                "Missing catalogue recipe: \(name.rawValue)"
            )
        }
    }

    func test_optional_calibration_recipes_registered_all_stacks() {
        let cat = FleetRecipesCatalogue.shared
        for stack in FleetAutopilotStack.allCases {
            for name in MissionRunReserveSwapTimeChecklist.optionalPostArmCalibrationRecipes(stack: stack) {
                XCTAssertNotNil(
                    cat.descriptor(for: name),
                    "Missing catalogue recipe for stack \(stack): \(name.rawValue)"
                )
            }
        }
    }

    func test_non_recipe_gates_stable() {
        XCTAssertEqual(
            MissionRunReserveSwapTimeChecklist.nonRecipeGates(stack: .ardupilot),
            MissionRunReserveSwapTimeChecklist.NonRecipeGate.allCases
        )
        XCTAssertEqual(
            MissionRunReserveSwapTimeChecklist.nonRecipeGates(stack: .px4).count,
            MissionRunReserveSwapTimeChecklist.NonRecipeGate.allCases.count
        )
    }
}

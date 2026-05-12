import XCTest
@testable import GuardianHQ

@MainActor
final class VehicleInspectorGuidedWizardControllerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
        FleetCalibrationRecipeRegistrations.registerAll()
    }

    func test_buildSteps_allGreen_returnsEmpty() {
        let items = [
            FleetCalibrationItem(id: .compass, status: .green, message: "ok"),
            FleetCalibrationItem(id: .accelerometer, status: .green, message: "ok"),
        ]
        let steps = VehicleInspectorGuidedWizardController.buildSteps(
            calibrationItems: items,
            isLiveMissionRecipeLocked: false
        )
        XCTAssertTrue(steps.isEmpty)
    }

    func test_buildSteps_errorSystemSortsBeforeWarning() {
        let items = [
            FleetCalibrationItem(id: .accelerometer, status: .warning, message: "w"),
            FleetCalibrationItem(id: .compass, status: .error, message: "e"),
        ]
        let steps = VehicleInspectorGuidedWizardController.buildSteps(
            calibrationItems: items,
            isLiveMissionRecipeLocked: false
        )
        XCTAssertFalse(steps.isEmpty, "Catalogue should yield at least one parameter-free Calibrate recipe after registerAll().")
        XCTAssertEqual(steps.first?.systemID, .compass, "Error status should order before warning in the guided queue.")
    }

    func test_operatorEmptyStateHeadline_barometer() {
        XCTAssertEqual(
            VehicleInspectorGuidedWizardController.operatorEmptyStateHeadline(for: .barometer),
            "Beginning calibration for Barometer…"
        )
    }

    func test_operatorNarrationBeforeRecipe_alias_matchesEmptyStateHeadline() {
        XCTAssertEqual(
            VehicleInspectorGuidedWizardController.operatorNarrationBeforeRecipe(for: .compass),
            VehicleInspectorGuidedWizardController.operatorEmptyStateHeadline(for: .compass)
        )
    }
}

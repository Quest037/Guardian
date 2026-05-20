import XCTest
@testable import GuardianCore

final class FleetTelemetryFieldCatalogRecipeDirectoryTests: XCTestCase {

    func test_calibrationSystemID_barometerRecipes_unique() {
        XCTAssertEqual(
            FleetTelemetryFieldCatalog.calibrationSystemID(forTelemetryDirectoryRecipe: .literal("recipe.fleet.calibrate.baro")),
            .barometer
        )
        XCTAssertEqual(
            FleetTelemetryFieldCatalog.calibrationSystemID(forTelemetryDirectoryRecipe: .literal("recipe.fleet.calibrate.baro.temperature")),
            .barometer
        )
    }

    func test_calibrationSystemID_compassPrimaryRecipe() {
        XCTAssertEqual(
            FleetTelemetryFieldCatalog.calibrationSystemID(forTelemetryDirectoryRecipe: .literal("recipe.fleet.calibrate.compass")),
            .compass
        )
    }

    func test_calibrationSystemID_sharedErrorFixRecipe_isAmbiguous_nil() {
        XCTAssertNil(
            FleetTelemetryFieldCatalog.calibrationSystemID(forTelemetryDirectoryRecipe: .literal("recipe.fleet.errors.fix.calibrationrequired")),
            "Listed under multiple systems — canvas must not pick an arbitrary marker."
        )
    }

    func test_calibrationSystemID_unknownRecipe_nil() {
        XCTAssertNil(
            FleetTelemetryFieldCatalog.calibrationSystemID(forTelemetryDirectoryRecipe: .literal("recipe.fleet.calibrate.nonexistent"))
        )
    }
}

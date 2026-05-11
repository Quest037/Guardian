import XCTest
@testable import GuardianHQ

final class FleetRecipeDescriptorLiveMissionPolicyTests: XCTestCase {

    func test_vehicleInspectorLaunchBlockedDuringLiveMission_groundOnly() {
        let d = FleetRecipeDescriptor(
            name: .literal("recipe.fleet.test.policy.ground"),
            humanLabel: "Ground",
            humanDescription: "Test",
            riskTier: .groundOnly
        )
        XCTAssertTrue(d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: true))
        XCTAssertFalse(d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: false))
    }

    func test_vehicleInspectorLaunchBlockedDuringLiveMission_confirmInLiveMission() {
        let d = FleetRecipeDescriptor(
            name: .literal("recipe.fleet.test.policy.confirm"),
            humanLabel: "Confirm",
            humanDescription: "Test",
            riskTier: .confirmInLiveMission
        )
        XCTAssertTrue(d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: true))
        XCTAssertFalse(d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: false))
    }

    func test_vehicleInspectorLaunchBlockedDuringLiveMission_safeInLiveMission() {
        let d = FleetRecipeDescriptor(
            name: .literal("recipe.fleet.test.policy.safe"),
            humanLabel: "Safe",
            humanDescription: "Test",
            riskTier: .safeInLiveMission
        )
        XCTAssertFalse(d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: true))
        XCTAssertFalse(d.vehicleInspectorLaunchBlockedDuringLiveMission(isVehicleInLiveMission: false))
    }
}

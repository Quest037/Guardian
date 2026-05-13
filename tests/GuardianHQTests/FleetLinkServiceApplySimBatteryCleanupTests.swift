import XCTest

@testable import GuardianHQ

@MainActor
final class FleetLinkServiceApplySimBatteryCleanupTests: XCTestCase {
    func test_applySimBatteryFullCharge_skipsWithoutGuardianSimStream() async {
        let fleet = FleetLinkService()
        await fleet.applySimBatteryFullChargeAfterRunCleanup(
            vehicleID: "sysid:1",
            autopilotStack: .px4,
            source: "unit.test.cleanup_battery"
        )
    }
}

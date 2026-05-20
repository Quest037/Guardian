import XCTest

@testable import GuardianCore

@MainActor
final class FleetLinkServiceMcrRosterChannelRegistryTests: XCTestCase {
    func test_release_last_ref_removes_registry_entry_new_channel_is_distinct_instance() {
        let fleet = FleetLinkService()
        let vid = "sysid:99"
        let first = fleet.mcrRosterLiveChannel(forVehicleID: vid)
        fleet.mcrRosterRetainLiveChannel(forVehicleID: vid)
        fleet.mcrRosterReleaseLiveChannel(forVehicleID: vid)
        let second = fleet.mcrRosterLiveChannel(forVehicleID: vid)
        XCTAssertNotEqual(
            ObjectIdentifier(first),
            ObjectIdentifier(second),
            "After refcount reaches zero the registry must drop the channel so churned ids do not pin one shell forever."
        )
    }

    func test_nested_retain_release_balances_before_removal() {
        let fleet = FleetLinkService()
        let vid = "sysid:7"
        let a = fleet.mcrRosterLiveChannel(forVehicleID: vid)
        fleet.mcrRosterRetainLiveChannel(forVehicleID: vid)
        fleet.mcrRosterRetainLiveChannel(forVehicleID: vid)
        fleet.mcrRosterReleaseLiveChannel(forVehicleID: vid)
        let mid = fleet.mcrRosterLiveChannel(forVehicleID: vid)
        XCTAssertEqual(ObjectIdentifier(a), ObjectIdentifier(mid))
        fleet.mcrRosterReleaseLiveChannel(forVehicleID: vid)
        let after = fleet.mcrRosterLiveChannel(forVehicleID: vid)
        XCTAssertNotEqual(ObjectIdentifier(a), ObjectIdentifier(after))
    }
}

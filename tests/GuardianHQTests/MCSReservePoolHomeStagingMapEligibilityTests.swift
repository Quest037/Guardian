import XCTest
@testable import GuardianCore

@MainActor
final class MCSReservePoolHomeStagingMapEligibilityTests: XCTestCase {
    func test_eligible_count_is_zero_for_empty_binding_slot() {
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let entries = [MissionRunReservePoolSlot(label: "empty", attachedDevice: "")]
        XCTAssertEqual(
            MCSReservePoolHomeStagingMapEligibility.eligibleSitlReservePoolSlotCount(
                entries: entries,
                sitl: sitl,
                fleetLink: fleet
            ),
            0
        )
    }

    func test_eligible_count_excludes_live_token_slot() {
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let entries = [
            MissionRunReservePoolSlot(
                label: "live",
                attachedFleetVehicleToken: FleetMissionVehicleToken.live.storageKey,
                attachedDevice: ""
            ),
        ]
        XCTAssertEqual(
            MCSReservePoolHomeStagingMapEligibility.eligibleSitlReservePoolSlotCount(
                entries: entries,
                sitl: sitl,
                fleetLink: fleet
            ),
            0
        )
    }

    func test_eligible_count_excludes_sitl_token_without_running_instance() {
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let ghost = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let entries = [
            MissionRunReservePoolSlot(
                label: "ghost",
                attachedFleetVehicleToken: FleetMissionVehicleToken.sitl(ghost).storageKey,
                attachedDevice: ""
            ),
        ]
        XCTAssertEqual(
            MCSReservePoolHomeStagingMapEligibility.eligibleSitlReservePoolSlotCount(
                entries: entries,
                sitl: sitl,
                fleetLink: fleet
            ),
            0
        )
    }
}

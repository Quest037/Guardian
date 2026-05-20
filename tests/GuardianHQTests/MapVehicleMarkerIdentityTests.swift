import XCTest

@testable import GuardianCore

final class MapVehicleMarkerIdentityTests: XCTestCase {

    func test_mission_run_assignment_matches_assignment_uuid_string() {
        let id = UUID()
        XCTAssertEqual(MapVehicleMarkerIdentity.missionRunAssignment(id), id.uuidString)
    }

    func test_floating_reserve_pool_matches_reserve_pool_encoder() {
        let task = UUID()
        let slot = UUID()
        XCTAssertEqual(
            MapVehicleMarkerIdentity.floatingReservePool(taskID: task, slotID: slot),
            MissionControlReservePoolMapMarkerID.encode(taskID: task, slotID: slot)
        )
    }

    func test_fleet_hub_vehicle_is_opaque_stream_id() {
        XCTAssertEqual(MapVehicleMarkerIdentity.fleetHubVehicle("veh-42"), "veh-42")
    }

    func test_sim_spawn_draft_is_stable_literal() {
        XCTAssertEqual(MapVehicleMarkerIdentity.simSpawnDraft, "sim-spawn-default")
    }
}

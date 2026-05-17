import XCTest
@testable import GuardianHQ

@MainActor
final class GuardianSitlFleetLinkReconnectPolicyTests: XCTestCase {
    func test_sitlSessionID_resolves_sysid_to_alive_instance() {
        let sitl = SitlService()
        let id = UUID()
        sitl.seedMissionRunTestSitlRunningInstance(id: id, stackInstanceIndex: 2)
        XCTAssertEqual(sitl.sitlSessionID(forGuardianVehicleID: "sysid:3"), id)
        XCTAssertNil(sitl.sitlSessionID(forGuardianVehicleID: "sysid:99"))
        XCTAssertNil(sitl.sitlSessionID(forGuardianVehicleID: "live"))
    }

    func test_mavlinkPositionTelemetryIsUp_requires_lat_and_lon() {
        let fleet = FleetLinkService()
        fleet.registerSimulatedVehicle(
            systemID: 1,
            mavlinkConnectionURL: "udpin://0.0.0.0:14550",
            autopilotStack: .px4,
            vehicleType: .uavCopter,
            spawnDefaults: SimSpawnDefaults.default
        )
        XCTAssertFalse(
            GuardianSitlFleetLinkReconnectPolicy.mavlinkPositionTelemetryIsUp(
                fleetLink: fleet,
                vehicleID: "sysid:1"
            ),
            "Spawn-default battery alone must not count as link up."
        )
    }

    func test_mayOfferReconnectLink_when_sim_alive_no_position_not_live() {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        sitl.seedMissionRunTestSitlRunningInstance(id: UUID(), stackInstanceIndex: 0)
        fleet.registerSimulatedVehicle(
            systemID: 1,
            mavlinkConnectionURL: "udpin://0.0.0.0:14550",
            autopilotStack: .px4,
            vehicleType: .uavCopter,
            spawnDefaults: .default
        )
        XCTAssertTrue(
            GuardianSitlFleetLinkReconnectPolicy.mayOfferReconnectLink(
                fleetLink: fleet,
                sitl: sitl,
                vehicleID: "sysid:1",
                lifecycleStage: .connecting
            )
        )
        XCTAssertFalse(
            GuardianSitlFleetLinkReconnectPolicy.mayOfferReconnectLink(
                fleetLink: fleet,
                sitl: sitl,
                vehicleID: "sysid:1",
                lifecycleStage: .live
            )
        )
    }

    func test_udpInboundListenPort_parses_udpin_url() {
        XCTAssertEqual(
            GuardianUdpPortUtilities.udpInboundListenPort(from: "udpin://0.0.0.0:14550"),
            14_550
        )
        XCTAssertNil(GuardianUdpPortUtilities.udpInboundListenPort(from: "udp://127.0.0.1:14550"))
    }
}

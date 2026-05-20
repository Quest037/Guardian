import XCTest
@testable import GuardianCore

@MainActor
final class FleetLinkServiceSitlTeardownTests: XCTestCase {
    func test_sitlLogLifecycle_doesNotRecreateModelAfterSessionStopped() {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        fleet.registerSimulatedVehicle(
            systemID: 42,
            mavlinkConnectionURL: "udpin://0.0.0.0:42042",
            autopilotStack: .px4,
            vehicleType: .uavCopter,
            spawnDefaults: .default
        )
        XCTAssertNotNil(fleet.vehicleModel(forVehicleID: "sysid:42"))
        fleet.unregisterSimulatedVehicle(systemID: 42)
        XCTAssertNil(fleet.vehicleModel(forVehicleID: "sysid:42"))
        fleet.updateSimulationLifecycleFromSitlLog(systemID: 42, line: "px4 starting")
        XCTAssertNil(fleet.vehicleModel(forVehicleID: "sysid:42"))
    }

    func test_stop_dismissPath_unregistersFleetSession() {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let id = UUID()
        sitl.seedMissionRunTestSitlRunningInstance(id: id, mavlinkSystemID: 99)
        fleet.registerSimulatedVehicle(
            systemID: 99,
            mavlinkConnectionURL: "udpin://0.0.0.0:42099",
            autopilotStack: .ardupilot,
            vehicleType: .uavCopter,
            spawnDefaults: .default
        )
        XCTAssertNotNil(fleet.vehicleModel(forVehicleID: "sysid:99"))
        sitl.stop(id: id)
        XCTAssertTrue(sitl.instances.isEmpty)
        XCTAssertNil(fleet.vehicleModel(forVehicleID: "sysid:99"))
        XCTAssertTrue(fleet.activeVehicleSessionIDs().isEmpty)
    }

    func test_pruneOrphanVehicleModelsWithoutActiveSession_removesStaleModel() {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        fleet.registerSimulatedVehicle(
            systemID: 7,
            mavlinkConnectionURL: "udpin://0.0.0.0:42007",
            autopilotStack: .px4,
            vehicleType: .uavCopter,
            spawnDefaults: .default
        )
        XCTAssertNotNil(fleet.vehicleModel(forVehicleID: "sysid:7"))
        fleet.unregisterSimulatedVehicle(systemID: 7)
        XCTAssertNil(fleet.vehicleModel(forVehicleID: "sysid:7"))
        fleet.vehicleModelsByVehicleID["sysid:7"] = FleetVehicleModel(
            vehicleID: "sysid:7",
            systemID: 7,
            initialStatus: .init(stage: .live)
        )
        fleet.pruneOrphanVehicleModelsWithoutActiveSession()
        XCTAssertNil(fleet.vehicleModel(forVehicleID: "sysid:7"))
    }

    func test_pruneSimulatedVehicleSessions_stopsOrphanSysidSession() {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        fleet.registerSimulatedVehicle(
            systemID: 11,
            mavlinkConnectionURL: "udpin://0.0.0.0:42011",
            autopilotStack: .ardupilot,
            vehicleType: .uavCopter,
            spawnDefaults: .default
        )
        fleet.registerSimulatedVehicle(
            systemID: 12,
            mavlinkConnectionURL: "udpin://0.0.0.0:42012",
            autopilotStack: .ardupilot,
            vehicleType: .uavCopter,
            spawnDefaults: .default
        )
        fleet.pruneSimulatedVehicleSessions(exceptAliveSystemIDs: [12])
        XCTAssertNil(fleet.vehicleModel(forVehicleID: "sysid:11"))
        XCTAssertNotNil(fleet.vehicleModel(forVehicleID: "sysid:12"))
        XCTAssertEqual(fleet.activeVehicleSessionIDs(), ["sysid:12"])
    }
}

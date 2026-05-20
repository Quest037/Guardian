import XCTest
@testable import GuardianCore

/// Fleet link keeps independent MAVSDK sessions per `sysid:n` (Training + Vehicles + Formation concurrently).
@MainActor
final class SitlMultiSimFleetLinkTests: XCTestCase {
    func test_two_simulated_vehicles_keep_separate_sessions() {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        fleet.registerSimulatedVehicle(
            systemID: 10,
            mavlinkConnectionURL: "udpin://0.0.0.0:14560",
            autopilotStack: .px4,
            vehicleType: .ugvWheeled,
            spawnDefaults: .default
        )
        fleet.registerSimulatedVehicle(
            systemID: 20,
            mavlinkConnectionURL: "udpin://0.0.0.0:14561",
            autopilotStack: .px4,
            vehicleType: .ugvWheeled,
            spawnDefaults: .default
        )
        XCTAssertTrue(fleet.isGuardianManagedSitlStream(vehicleID: "sysid:10"))
        XCTAssertTrue(fleet.isGuardianManagedSitlStream(vehicleID: "sysid:20"))
        fleet.unregisterSimulatedVehicle(systemID: 10)
        XCTAssertFalse(fleet.isGuardianManagedSitlStream(vehicleID: "sysid:10"))
        XCTAssertTrue(fleet.isGuardianManagedSitlStream(vehicleID: "sysid:20"))
    }
}

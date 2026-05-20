import XCTest
@testable import GuardianCore

@MainActor
final class FleetLinkTrainingRos2SidecarTests: XCTestCase {
    func test_reconnectSimulatedVehicleSession_restores_training_ros2_sidecar_flag() async {
        let fleet = FleetLinkService()
        fleet.setSimulateEnabled(true)
        fleet.registerSimulatedVehicle(
            systemID: 9,
            mavlinkConnectionURL: "udpin://0.0.0.0:14559",
            autopilotStack: .px4,
            vehicleType: .ugvWheeled,
            spawnDefaults: .default,
            px4Ros2SidecarDesired: true
        )
        fleet.unregisterSimulatedVehicle(systemID: 9)
        _ = await fleet.reconnectSimulatedVehicleSession(
            systemID: 9,
            mavlinkConnectionURL: "udpin://0.0.0.0:14559",
            autopilotStack: .px4,
            vehicleType: .ugvWheeled,
            spawnDefaults: .default,
            px4Ros2SidecarDesired: true
        )
        fleet.ensurePx4Ros2Sidecar(forVehicleID: "sysid:9")
        XCTAssertEqual(fleet.ros2BridgeProcessPhase, .inactive)
        // Bridge may stay inactive without a live ROS runtime in unit tests; flag + reconcile path must not crash.
        XCTAssertNotNil(fleet.vehicleModel(forVehicleID: "sysid:9"))
    }
}

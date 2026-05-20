import XCTest

@testable import GuardianCore

final class TrainingLabGazeboProxyTelemetrySyncTests: XCTestCase {
    func test_mavlinkSystemID_parses_sysid_vehicle_key() {
        XCTAssertEqual(
            TrainingLabGazeboProxyTelemetrySync.mavlinkSystemID(from: "sysid:202"),
            202
        )
        XCTAssertNil(TrainingLabGazeboProxyTelemetrySync.mavlinkSystemID(from: "UAV-V:1"))
    }

    func test_environmentPose_maps_hub_lat_lon_to_enu() {
        let origin = SimSpawnDefaults(
            latitudeDeg: 47.39775,
            longitudeDeg: 8.54493,
            altitudeM: 0,
            headingDeg: 0
        )
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 47.397766
        hub.longitudeDeg = 8.544599
        hub.headingDeg = 95
        hub.absoluteAltM = 0
        let pose = TrainingLabGazeboProxyTelemetrySync.environmentPose(
            hub: hub,
            mapGeodeticOrigin: origin
        )
        XCTAssertNotNil(pose)
        XCTAssertEqual(pose?.yawDeg, 95, accuracy: 0.01)
        XCTAssertEqual(pose?.zM, WorldBuilderZoneBoundsCheck.mapBaseTopZM, accuracy: 0.001)
        XCTAssertNotEqual(pose?.xM, 0, accuracy: 0.01)
    }
}

import XCTest

@testable import GuardianCore

final class FleetSimStateSimHomeRestoreSnapshotTests: XCTestCase {
    func test_simHomeRestoreSnapshotFromHub_nilWithoutLatLon() {
        let hub = FleetHubVehicleTelemetry.empty
        XCTAssertNil(FleetSimState(simHomeRestoreSnapshotFrom: hub))
    }

    func test_simHomeRestoreSnapshotFromHub_populatesPose() throws {
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = -33.5
        hub.longitudeDeg = 151.2
        hub.absoluteAltM = 25
        hub.headingDeg = 90
        let a = try XCTUnwrap(FleetSimState(simHomeRestoreSnapshotFrom: hub))
        XCTAssertEqual(a.latitudeDeg, -33.5, accuracy: 0.0001)
        XCTAssertEqual(a.longitudeDeg, 151.2, accuracy: 0.0001)
        XCTAssertEqual(a.absoluteAltitudeM, 25)
        XCTAssertEqual(a.yawDeg, 90)
        XCTAssertNil(a.batteryVoltageV)
        XCTAssertNil(a.ardupilotSimBattCapAh)
        XCTAssertNil(a.px4SimBatDrain)
    }

    func test_simHomeRestoreSnapshotFromHub_fallsBackToYawWhenHeadingNil() throws {
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 0
        hub.longitudeDeg = 1
        hub.yawDeg = 45
        hub.headingDeg = nil
        let a = try XCTUnwrap(FleetSimState(simHomeRestoreSnapshotFrom: hub))
        XCTAssertEqual(a.yawDeg, 45)
    }

    func test_reservePoolSimHomeRestore_nilWithoutHubLatLonAndNoBulk() {
        XCTAssertNil(FleetSimState(reservePoolSimHomeRestoreStartPose: nil, bulkHome: nil))
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = nil
        hub.longitudeDeg = nil
        XCTAssertNil(FleetSimState(reservePoolSimHomeRestoreStartPose: hub, bulkHome: nil))
    }

    func test_reservePoolSimHomeRestore_bulkOnly() throws {
        let bulk = RouteCoordinate(lat: -34, lon: 150)
        let a = try XCTUnwrap(FleetSimState(reservePoolSimHomeRestoreStartPose: nil, bulkHome: bulk))
        XCTAssertEqual(a.latitudeDeg, -34)
        XCTAssertEqual(a.longitudeDeg, 150)
        XCTAssertNil(a.absoluteAltitudeM)
        XCTAssertEqual(a.yawDeg, 0)
    }

    func test_reservePoolSimHomeRestore_prefersHubLatLonAndMergesAltYaw() throws {
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 1
        hub.longitudeDeg = 2
        hub.absoluteAltM = 30
        hub.headingDeg = 180
        let bulk = RouteCoordinate(lat: 99, lon: 99)
        let a = try XCTUnwrap(FleetSimState(reservePoolSimHomeRestoreStartPose: hub, bulkHome: bulk))
        XCTAssertEqual(a.latitudeDeg, 1)
        XCTAssertEqual(a.longitudeDeg, 2)
        XCTAssertEqual(a.absoluteAltitudeM, 30)
        XCTAssertEqual(a.yawDeg, 180)
    }
}

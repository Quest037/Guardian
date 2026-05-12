import XCTest
@testable import GuardianHQ

/// Pins ``FleetCommandStackConverterShared/translateMovePoint`` yaw semantics for
/// ground/surface frames (bearing hub → target) vs airframes (caller yaw preserved).
final class FleetCommandStackConverterMovePointTests: XCTestCase {

    private func gotoYaw(from translation: FleetCommandStackTranslation) -> Double? {
        guard case let .vehicleCommands(cmds) = translation,
              let first = cmds.first,
              case let .gotoCoordinate(_, _, yaw) = first
        else { return nil }
        return yaw
    }

    func test_explicit_ugv_usesBearingWhenHubSeparatedFromTarget() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 37.0
        hub.longitudeDeg = -122.0
        let ctx = FleetCommandStackConverterContext(
            vehicleID: "v1",
            vehicleType: .ugvWheeled,
            hubTelemetry: hub
        )
        let params = FleetCommandParameters(values: [
            "pointKind": .string("explicit"),
            "latitudeDeg": .double(37.001),
            "longitudeDeg": .double(-122.0),
            "relativeAltitudeM": .double(0),
            "yawDeg": .double(999)
        ])
        let t = FleetCommandStackConverterShared.translateMovePoint(parameters: params, context: ctx)
        let expected = MissionTelemetryGeo.bearingDegrees(
            lat1: 37.0,
            lon1: -122.0,
            lat2: 37.001,
            lon2: -122.0
        )
        guard let yaw = gotoYaw(from: t) else {
            XCTFail("expected vehicleCommands with gotoCoordinate")
            return
        }
        XCTAssertEqual(yaw, expected, accuracy: 0.05)
        XCTAssertNotEqual(yaw, 999, accuracy: 0.01)
    }

    func test_explicit_uav_preservesRequestedYaw() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 37.0
        hub.longitudeDeg = -122.0
        let ctx = FleetCommandStackConverterContext(
            vehicleID: "v1",
            vehicleType: .uavCopter,
            hubTelemetry: hub
        )
        let params = FleetCommandParameters(values: [
            "pointKind": .string("explicit"),
            "latitudeDeg": .double(37.001),
            "longitudeDeg": .double(-122.0),
            "relativeAltitudeM": .double(2),
            "yawDeg": .double(42.5)
        ])
        let t = FleetCommandStackConverterShared.translateMovePoint(parameters: params, context: ctx)
        guard let yaw = gotoYaw(from: t) else {
            XCTFail("expected vehicleCommands with gotoCoordinate")
            return
        }
        XCTAssertEqual(yaw, 42.5, accuracy: 0.001)
    }

    func test_explicit_ugv_withoutHubPosition_fallsBackToRequestedYaw() {
        let ctx = FleetCommandStackConverterContext(
            vehicleID: "v1",
            vehicleType: .ugvWheeled,
            hubTelemetry: nil
        )
        let params = FleetCommandParameters(values: [
            "pointKind": .string("explicit"),
            "latitudeDeg": .double(37.001),
            "longitudeDeg": .double(-122.0),
            "relativeAltitudeM": .double(0),
            "yawDeg": .double(77)
        ])
        let t = FleetCommandStackConverterShared.translateMovePoint(parameters: params, context: ctx)
        guard let yaw = gotoYaw(from: t) else {
            XCTFail("expected vehicleCommands with gotoCoordinate")
            return
        }
        XCTAssertEqual(yaw, 77, accuracy: 0.001)
    }

    func test_explicit_ugv_coincidentWithHub_keepsRequestedYaw() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.latitudeDeg = 37.0
        hub.longitudeDeg = -122.0
        let ctx = FleetCommandStackConverterContext(
            vehicleID: "v1",
            vehicleType: .ugvTracked,
            hubTelemetry: hub
        )
        let params = FleetCommandParameters(values: [
            "pointKind": .string("explicit"),
            "latitudeDeg": .double(37.0),
            "longitudeDeg": .double(-122.0),
            "relativeAltitudeM": .double(0),
            "yawDeg": .double(88)
        ])
        let t = FleetCommandStackConverterShared.translateMovePoint(parameters: params, context: ctx)
        guard let yaw = gotoYaw(from: t) else {
            XCTFail("expected vehicleCommands with gotoCoordinate")
            return
        }
        XCTAssertEqual(yaw, 88, accuracy: 0.001)
    }
}

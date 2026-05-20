import XCTest
@testable import GuardianCore

@MainActor
final class FleetVehicleDoParkCommandTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    private func telemetryWithKnownPosition() -> FleetHubVehicleTelemetry {
        var telemetry = FleetHubVehicleTelemetry.empty
        telemetry.latitudeDeg = 51.5074
        telemetry.longitudeDeg = -0.1278
        telemetry.absoluteAltM = 35.0
        telemetry.relativeAltM = 5.0
        telemetry.altitudeAmslM = 35.0
        telemetry.headingDeg = 90.0
        return telemetry
    }

    func test_doPark_arduPilot_translatesToParkVehicleCommand() {
        let converter = FleetCommandStackConverterArduPilot()
        let context = FleetCommandStackConverterContext(
            vehicleID: "TEST-PARK-1",
            vehicleType: .uavCopter,
            hubTelemetry: telemetryWithKnownPosition()
        )
        let t = converter.translate(
            commandName: .fleetVehicleDoPark,
            parameters: .empty,
            context: context
        )
        guard case .vehicleCommands(let cmds) = t else {
            return XCTFail("expected vehicleCommands, got \(t)")
        }
        XCTAssertEqual(cmds, [.park])
    }

    func test_doPark_px4_translatesToParkVehicleCommand() {
        let converter = FleetCommandStackConverterPX4()
        let context = FleetCommandStackConverterContext(
            vehicleID: "TEST-PARK-2",
            vehicleType: .ugvWheeled,
            hubTelemetry: telemetryWithKnownPosition()
        )
        let t = converter.translate(
            commandName: .fleetVehicleDoPark,
            parameters: .empty,
            context: context
        )
        guard case .vehicleCommands(let cmds) = t else {
            return XCTFail("expected vehicleCommands, got \(t)")
        }
        XCTAssertEqual(cmds, [.park])
    }

    func test_doPark_descriptor_registered() {
        let d = FleetCommandsCatalogue.shared.descriptor(for: .fleetVehicleDoPark)
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.riskTier, .confirmInLiveMission)
        XCTAssertTrue(d?.parameters.isEmpty ?? false)
    }

    func test_doPark_descriptor_documents_mission_pause() {
        let d = FleetCommandsCatalogue.shared.descriptor(for: .fleetVehicleDoPark)
        let text = d?.humanDescription.lowercased() ?? ""
        XCTAssertTrue(text.contains("pause"), "Park catalogue copy should mention mission pause before class-specific steps")
    }

    func test_doPark_descriptor_documents_px4_ugv_w_set_mode_hold_first_stop() {
        let d = FleetCommandsCatalogue.shared.descriptor(for: .fleetVehicleDoPark)
        let text = d?.humanDescription.lowercased() ?? ""
        XCTAssertTrue(text.contains("ugv-w"), "Park catalogue copy should document PX4 UGV-W first-stop behaviour")
        XCTAssertTrue(text.contains("set_mode"), "Park catalogue copy should mention SET_MODE for the first hold on that path")
        XCTAssertFalse(text.contains("manual"), "Park should not document a manual pre-step")
    }
}

import XCTest
@testable import GuardianHQ

final class FleetVehicleDoOffboardStopTranslationTests: XCTestCase {

    private func ctx() -> FleetCommandStackConverterContext {
        FleetCommandStackConverterContext(
            vehicleID: "TEST-UGV-1",
            vehicleType: .ugvWheeled,
            hubTelemetry: nil
        )
    }

    func test_pX4_translates_do_offboard_stop_to_vehicle_command() {
        let t = FleetCommandStackConverterPX4().translate(
            commandName: .fleetVehicleDoOffboardStop,
            parameters: .empty,
            context: ctx()
        )
        guard case .vehicleCommands(let cmds) = t else {
            return XCTFail("Expected vehicleCommands")
        }
        XCTAssertEqual(cmds, [.offboardStop])
    }

    func test_arduPilot_translates_do_offboard_stop_to_vehicle_command() {
        let t = FleetCommandStackConverterArduPilot().translate(
            commandName: .fleetVehicleDoOffboardStop,
            parameters: .empty,
            context: ctx()
        )
        guard case .vehicleCommands(let cmds) = t else {
            return XCTFail("Expected vehicleCommands")
        }
        XCTAssertEqual(cmds, [.offboardStop])
    }
}

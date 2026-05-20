import XCTest

@testable import GuardianCore

final class FleetVehicleCommandMissionRunDispatchShortLabelTests: XCTestCase {
    func test_arm() {
        XCTAssertEqual(FleetVehicleCommand.arm.missionRunDispatchShortLabel, "arm")
    }

    func test_mission_clear() {
        XCTAssertEqual(FleetVehicleCommand.missionClear.missionRunDispatchShortLabel, "mission clear")
    }

    func test_return_to_launch() {
        XCTAssertEqual(FleetVehicleCommand.returnToLaunch.missionRunDispatchShortLabel, "return to launch")
    }
}

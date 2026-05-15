import XCTest

@testable import GuardianHQ

final class GuardianMapVehicleGlyphKindTests: XCTestCase {

    func test_forFleetVehicleType_uav_classes_map_to_arrow() {
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.uavCopter), .uavArrow)
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.uavFixedWing), .uavArrow)
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.uavVTOL), .uavArrow)
    }

    func test_forFleetVehicleType_ugv_and_unknown_map_to_square() {
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.ugvWheeled), .ugvSquare)
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.ugvTracked), .ugvSquare)
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.ugvLegged), .ugvSquare)
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.unknown), .ugvSquare)
    }

    func test_forFleetVehicleType_surface_underwater_map_to_cross() {
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.usv), .usvUuvCross)
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forFleetVehicleType(.uuv), .usvUuvCross)
    }

    func test_forRosterAssignment_uses_mission_roster_device_class() {
        let rd = RosterDevice(name: "R", vehicleClass: .uavFixedWing)
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [])
        )
        let assign = MissionRunAssignment(id: UUID(), rosterDeviceId: rd.id, slotName: "P1")
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forRosterAssignment(assign, mission: mission), .uavArrow)
    }

    func test_forRosterAssignment_missing_device_falls_back_to_unknown_square() {
        let mission = Mission(id: UUID(), name: "M", description: "", type: .mobile)
        let assign = MissionRunAssignment(id: UUID(), rosterDeviceId: UUID(), slotName: "P1")
        XCTAssertEqual(GuardianMapVehicleGlyphKind.forRosterAssignment(assign, mission: mission), .ugvSquare)
    }
}

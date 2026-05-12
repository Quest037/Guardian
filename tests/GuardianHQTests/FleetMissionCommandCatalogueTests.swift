import Mavsdk
import XCTest
@testable import GuardianHQ

/// Registration + translation coverage for the MAVSDK `Mission` plugin command family
/// (`command.fleet.vehicle.do.mission.*`, `get.mission.*`, `cancel.mission.*`).
final class FleetMissionCommandCatalogueTests: XCTestCase {

    func test_mission_command_name_literals_validate() {
        let raws = [
            "command.fleet.vehicle.do.mission.clear",
            "command.fleet.vehicle.do.mission.start",
            "command.fleet.vehicle.do.mission.pause",
            "command.fleet.vehicle.do.mission.jump.to",
            "command.fleet.vehicle.do.mission.download",
            "command.fleet.vehicle.do.mission.upload.with.progress",
            "command.fleet.vehicle.do.mission.download.with.progress",
            "command.fleet.vehicle.do.mission.rtl.after.set",
            "command.fleet.vehicle.do.mission.upload.start",
            "command.fleet.vehicle.get.mission.finished",
            "command.fleet.vehicle.get.mission.rtl.after",
            "command.fleet.vehicle.cancel.mission.upload",
            "command.fleet.vehicle.cancel.mission.download",
        ]
        for raw in raws {
            XCTAssertTrue(
                FleetCommandName.isValidRawValue(raw),
                "Expected valid literal: \(raw)"
            )
        }
    }

    func test_translate_jump_to_without_index_is_not_implemented() {
        guard let t = FleetCommandStackConverterShared.translateFleetVehicleMissionIfNeeded(
            commandName: .fleetVehicleDoMissionJumpTo,
            parameters: .empty
        ) else {
            return XCTFail("expected mission translation")
        }
        guard case .notImplemented(let detail) = t else {
            return XCTFail("expected .notImplemented, got \(String(describing: t))")
        }
        XCTAssertTrue(detail.contains("index"))
    }

    func test_translate_jump_to_with_index_emits_set_current_item() {
        let params = FleetCommandParameters(values: ["index": .integer(3)])
        guard let t = FleetCommandStackConverterShared.translateFleetVehicleMissionIfNeeded(
            commandName: .fleetVehicleDoMissionJumpTo,
            parameters: params
        ) else {
            return XCTFail("expected mission translation")
        }
        guard case .vehicleCommands(let cmds) = t else {
            return XCTFail("expected .vehicleCommands, got \(String(describing: t))")
        }
        XCTAssertEqual(cmds, [.missionSetCurrentItem(index: 3)])
    }

    func test_translate_mission_clear_emits_clear() {
        guard let t = FleetCommandStackConverterShared.translateFleetVehicleMissionIfNeeded(
            commandName: .fleetVehicleDoMissionClear,
            parameters: .empty
        ) else {
            return XCTFail("expected mission translation")
        }
        guard case .vehicleCommands(let cmds) = t else {
            return XCTFail("expected .vehicleCommands, got \(String(describing: t))")
        }
        XCTAssertEqual(cmds, [.missionClear])
    }

    func test_mission_upload_start_composite_orders_upload_arm_start() async {
        let contains = await MainActor.run {
            FleetCommandsCatalogueBootstrap.ensureRegistered()
            return FleetCommandsCatalogue.shared
                .descriptor(for: .fleetVehicleDoMissionUploadStart)?
                .containsCommands
        }
        XCTAssertEqual(
            contains,
            [
                .fleetVehicleDoMissionUpload,
                .fleetVehicleDoArm,
                .fleetVehicleDoMissionStart,
            ],
            "`do.mission.upload.start` must mirror MRE upload+arm+start ordering."
        )
    }

    func test_mission_item_json_encode_decode_roundTrip() throws {
        let original = FleetVehicleCommandMissionItemPayload(
            latitudeDeg: -33.857,
            longitudeDeg: 151.215,
            relativeAltitudeM: 30,
            speedMS: 5,
            isFlyThrough: false,
            gimbalPitchDeg: 0,
            gimbalYawDeg: 0,
            cameraAction: "takePhoto",
            loiterTimeS: 0,
            cameraPhotoIntervalS: 0,
            acceptanceRadiusM: 2,
            yawDeg: 90,
            cameraPhotoDistanceM: 0
        )
        let data = try JSONEncoder().encode([original])
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let items = try FleetVehicleCommandMissionItemPayload.decodeMissionItems(fromJSON: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].latitudeDeg, original.latitudeDeg, accuracy: 0.000_001)
        XCTAssertEqual(items[0].longitudeDeg, original.longitudeDeg, accuracy: 0.000_001)
        XCTAssertEqual(items[0].cameraAction, Mavsdk.Mission.MissionItem.CameraAction.takePhoto)
    }
}

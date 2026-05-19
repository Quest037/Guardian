import XCTest

@testable import GuardianHQ

final class GuardianBrainRunUtilitiesTests: XCTestCase {
    func test_structuredBrainExportHeader_includes_ids_and_versions() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let bindings = [
            MissionRunBrainBinding(
                taskKindRaw: TrainingTaskKind.reverseIntoSlot.rawValue,
                vehicleClassRaw: TrainingVehicleClass.ugvWheeled.rawValue,
                brainId: id,
                brainVersion: GuardianBrainVersion.fromLegacyInteger(2)
                displayName: "Parking"
            ),
        ]
        let header = GuardianBrainRunUtilities.structuredBrainExportHeader(bindings: bindings)
        XCTAssertTrue(header.contains("# Guardian brain bindings"))
        XCTAssertTrue(header.contains(id.uuidString))
        XCTAssertTrue(header.contains("\"brain_version\":\"0.0.2\""))
        XCTAssertTrue(header.contains("\"major_line\":\"subodai\""))
        XCTAssertTrue(header.contains("\"format_version\":\(GuardianBrainPackFormat.currentFormatVersion)"))
    }

    func test_preferredBinding_matches_fleet_vehicle_type() {
        let binding = MissionRunBrainBinding(
            taskKindRaw: TrainingTaskKind.approachSlotForward.rawValue,
            vehicleClassRaw: TrainingVehicleClass.ugvTracked.rawValue,
            brainId: UUID(),
            brainVersion: GuardianBrainVersion.fromLegacyInteger(1)
            displayName: "Tracked"
        )
        XCTAssertEqual(
            GuardianBrainRunUtilities.preferredBinding(for: .ugvTracked, bindings: [binding])?.brainId,
            binding.brainId
        )
        XCTAssertNil(GuardianBrainRunUtilities.preferredBinding(for: .usv, bindings: [binding]))
    }
}

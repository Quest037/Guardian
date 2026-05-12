import XCTest

@testable import GuardianHQ

final class MissionRunReserveRecipeRunnerCorrelationTests: XCTestCase {

    func test_floating_pool_factory_uses_slot_id_for_stream_and_pool() {
        let slot = MissionRunReservePoolSlot(label: "R1", attachedFleetVehicleToken: "tok")
        let c = MissionRunReserveRecipeRunnerCorrelation.floatingPoolReserve(
            missionRunID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            missionTaskID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            vacancyAssignmentID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            poolSlot: slot,
            vehicleID: "veh-a"
        )
        XCTAssertEqual(c.reserveStreamAssignmentID, slot.id)
        XCTAssertEqual(c.reservePoolSlotID, slot.id)
    }

    func test_recipe_runner_source_shape_and_sanitizes_vehicle_id() {
        let mr = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let mt = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
        let vac = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
        let rsv = UUID(uuidString: "10000000-0000-0000-0000-000000000004")!
        let pool = UUID(uuidString: "10000000-0000-0000-0000-000000000005")!
        let c = MissionRunReserveRecipeRunnerCorrelation(
            missionRunID: mr,
            missionTaskID: mt,
            vacancyAssignmentID: vac,
            reserveStreamAssignmentID: rsv,
            reservePoolSlotID: pool,
            vehicleID: "v|x"
        )
        let s = c.recipeRunnerSource(phase: .swapTimeChecks)
        XCTAssertTrue(s.hasPrefix(MissionRunReserveRecipeRunnerCorrelation.recipeRunnerSourceNamespace + ".swapTimeChecks|"))
        XCTAssertTrue(s.contains("mr=\(mr.uuidString)"))
        XCTAssertTrue(s.contains("mt=\(mt.uuidString)"))
        XCTAssertTrue(s.contains("vac=\(vac.uuidString)"))
        XCTAssertTrue(s.contains("rsv=\(rsv.uuidString)"))
        XCTAssertTrue(s.contains("pool=\(pool.uuidString)"))
        XCTAssertTrue(s.contains("v=v_x"))
    }

    func test_fixed_reserve_uses_nil_pool_token_in_source() {
        let reserve = MissionRunAssignment(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
            taskId: nil,
            rosterDeviceId: UUID(),
            slotName: "Res",
            attachedFleetVehicleToken: "k"
        )
        let c = MissionRunReserveRecipeRunnerCorrelation.fixedRosterReserve(
            missionRunID: UUID(),
            missionTaskID: UUID(),
            vacancyAssignmentID: UUID(),
            reserveAssignment: reserve,
            vehicleID: "z"
        )
        XCTAssertNil(c.reservePoolSlotID)
        let s = c.recipeRunnerSource(phase: .missionUpload)
        XCTAssertTrue(s.contains("pool=-"), s)
    }
}

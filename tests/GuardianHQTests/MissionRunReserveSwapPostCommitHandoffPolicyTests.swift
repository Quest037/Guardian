import XCTest
@testable import GuardianCore

final class MissionRunReserveSwapPostCommitHandoffPolicyTests: XCTestCase {

    func test_resolve_success_when_tokens_differ() {
        let vacId = UUID()
        let poolId = UUID()
        let rosterId = UUID()
        let vac = MissionRunAssignment(
            id: vacId,
            rosterDeviceId: rosterId,
            slotName: "P1",
            attachedFleetVehicleToken: "fleet:reserve"
        )
        let displaced = MissionRunAssignment(
            id: poolId,
            rosterDeviceId: rosterId,
            slotName: "pool-1",
            attachedFleetVehicleToken: "fleet:active"
        )
        let r = MissionRunReserveSwapPostCommitStreamResolver.resolve(
            assignments: [vac, displaced],
            vacancyAssignmentID: vacId,
            displacedStreamAssignmentID: poolId
        )
        guard case .resolved(let snap) = r else {
            return XCTFail("expected resolved")
        }
        XCTAssertEqual(snap.vacancyFleetStorageKey, "fleet:reserve")
        XCTAssertEqual(snap.displacedFleetStorageKey, "fleet:active")
    }

    func test_resolve_missing_vacancy() {
        let poolId = UUID()
        let displaced = MissionRunAssignment(id: poolId, rosterDeviceId: UUID(), slotName: "pool", attachedFleetVehicleToken: "a")
        let r = MissionRunReserveSwapPostCommitStreamResolver.resolve(
            assignments: [displaced],
            vacancyAssignmentID: UUID(),
            displacedStreamAssignmentID: poolId
        )
        XCTAssertEqual(r, .missingVacancyAssignment)
    }

    func test_resolve_identical_tokens_fails() {
        let a = UUID()
        let b = UUID()
        let vac = MissionRunAssignment(id: a, rosterDeviceId: UUID(), slotName: "P1", attachedFleetVehicleToken: "same")
        let dis = MissionRunAssignment(id: b, rosterDeviceId: UUID(), slotName: "pool", attachedFleetVehicleToken: "same")
        let r = MissionRunReserveSwapPostCommitStreamResolver.resolve(
            assignments: [vac, dis],
            vacancyAssignmentID: a,
            displacedStreamAssignmentID: b
        )
        XCTAssertEqual(r, .identicalFleetBindingsAfterCommit)
    }

    /// Production floating pool swaps: displaced binding lives on the pool slot, not as a ``MissionRunAssignment`` row.
    func test_resolve_success_floating_pool_berth_without_displaced_assignment_row() {
        let vacId = UUID()
        let poolSlotId = UUID()
        let rosterId = UUID()
        let vac = MissionRunAssignment(
            id: vacId,
            rosterDeviceId: rosterId,
            slotName: "P1",
            attachedFleetVehicleToken: "fleet:reserve"
        )
        let pool = MissionRunReservePool(entries: [
            MissionRunReservePoolSlot(
                id: poolSlotId,
                label: "pool-1",
                attachedFleetVehicleToken: "fleet:active"
            ),
        ])
        let r = MissionRunReserveSwapPostCommitStreamResolver.resolve(
            assignments: [vac],
            vacancyAssignmentID: vacId,
            displacedStreamAssignmentID: poolSlotId,
            floatingReservePool: pool,
            floatingReservePoolSlotID: poolSlotId
        )
        guard case .resolved(let snap) = r else {
            return XCTFail("expected resolved")
        }
        XCTAssertEqual(snap.vacancyFleetStorageKey, "fleet:reserve")
        XCTAssertEqual(snap.displacedFleetStorageKey, "fleet:active")
    }

    func test_resolve_missing_displaced_when_floating_slot_id_set_but_pool_has_no_matching_entry() {
        let vacId = UUID()
        let rosterId = UUID()
        let vac = MissionRunAssignment(
            id: vacId,
            rosterDeviceId: rosterId,
            slotName: "P1",
            attachedFleetVehicleToken: "fleet:a"
        )
        let wrongSlot = UUID()
        let pool = MissionRunReservePool(entries: [
            MissionRunReservePoolSlot(id: UUID(), label: "other", attachedFleetVehicleToken: "fleet:b"),
        ])
        let r = MissionRunReserveSwapPostCommitStreamResolver.resolve(
            assignments: [vac],
            vacancyAssignmentID: vacId,
            displacedStreamAssignmentID: wrongSlot,
            floatingReservePool: pool,
            floatingReservePoolSlotID: wrongSlot
        )
        XCTAssertEqual(r, .missingDisplacedStreamAssignment)
    }
}

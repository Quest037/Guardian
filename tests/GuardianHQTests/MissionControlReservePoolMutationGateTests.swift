import XCTest
@testable import GuardianCore

final class MissionControlReservePoolMutationGateTests: XCTestCase {

    private let t1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let t2 = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let s1 = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let s2 = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    private let v1 = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!

    func test_swapOperationInFlight_nil_false() {
        XCTAssertFalse(MissionControlReservePoolMutationGate.swapOperationInFlight(lock: nil))
    }

    func test_swapOperationInFlight_some_true() {
        let lock = MissionControlReservePoolMutationGate.SwapOperationLock(
            vacancyAssignmentID: v1,
            taskID: t1,
            poolSlotID: s1
        )
        XCTAssertTrue(MissionControlReservePoolMutationGate.swapOperationInFlight(lock: lock))
    }

    func test_reservePoolSlotMutationLocked_swapLock_same_slot() {
        let lock = MissionControlReservePoolMutationGate.SwapOperationLock(
            vacancyAssignmentID: v1,
            taskID: t1,
            poolSlotID: s1
        )
        XCTAssertTrue(
            MissionControlReservePoolMutationGate.reservePoolSlotMutationLocked(
                swapLock: lock,
                berthPreflightTaskID: nil,
                berthPreflightSlotID: nil,
                taskID: t1,
                slotID: s1
            )
        )
    }

    func test_reservePoolSlotMutationLocked_swapLock_other_slot_false() {
        let lock = MissionControlReservePoolMutationGate.SwapOperationLock(
            vacancyAssignmentID: v1,
            taskID: t1,
            poolSlotID: s1
        )
        XCTAssertFalse(
            MissionControlReservePoolMutationGate.reservePoolSlotMutationLocked(
                swapLock: lock,
                berthPreflightTaskID: nil,
                berthPreflightSlotID: nil,
                taskID: t1,
                slotID: s2
            )
        )
    }

    func test_reservePoolSlotMutationLocked_berthPreflight_same_slot() {
        XCTAssertTrue(
            MissionControlReservePoolMutationGate.reservePoolSlotMutationLocked(
                swapLock: nil,
                berthPreflightTaskID: t2,
                berthPreflightSlotID: s2,
                taskID: t2,
                slotID: s2
            )
        )
    }

    func test_reservePoolSlotMutationLocked_berthPreflight_partial_nil_false() {
        XCTAssertFalse(
            MissionControlReservePoolMutationGate.reservePoolSlotMutationLocked(
                swapLock: nil,
                berthPreflightTaskID: t2,
                berthPreflightSlotID: nil,
                taskID: t2,
                slotID: s2
            )
        )
    }
}

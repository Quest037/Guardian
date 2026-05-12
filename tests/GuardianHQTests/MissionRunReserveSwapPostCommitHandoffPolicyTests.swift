import XCTest
@testable import GuardianHQ

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
}

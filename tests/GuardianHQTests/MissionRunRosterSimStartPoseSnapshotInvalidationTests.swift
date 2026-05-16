import Foundation
import XCTest

@testable import GuardianHQ

@MainActor
final class MissionRunRosterSimStartPoseSnapshotInvalidationTests: XCTestCase {

    private func sampleMissionWithTwoRosterSlots() -> (mission: Mission, task: MissionTask, rd1: UUID, rd2: UUID) {
        let rd1 = UUID()
        let rd2 = UUID()
        let task = MissionTask(name: "T", rosterDeviceIds: [rd1, rd2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rd1, name: "A"),
                RosterDevice(id: rd2, name: "B"),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        return (mission, task, rd1, rd2)
    }

    private func dummySimState() -> FleetSimState {
        FleetSimState(
            latitudeDeg: 1,
            longitudeDeg: 2,
            absoluteAltitudeM: 3,
            yawDeg: 4,
            batteryVoltageV: nil,
            ardupilotSimBattCapAh: nil,
            px4SimBatDrain: nil
        )
    }

    func test_updateTemplate_nil_clears_roster_sim_snapshots() {
        let (mission, task, rd1, _) = sampleMissionWithTwoRosterSlots()
        let aid = UUID()
        let row = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "S1",
            attachedDevice: "CALL1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        let snap = dummySimState()
        run.unitTestingReplaceRosterSimStartPoseSnapshots([aid: snap])
        XCTAssertEqual(run.rosterSimStartPoseSnapshotByAssignmentID[aid], snap)

        run.updateTemplate(nil)

        XCTAssertTrue(run.rosterSimStartPoseSnapshotByAssignmentID.isEmpty)
    }

    func test_updateTemplate_nil_clears_operator_launch_poses() {
        let (mission, task, rd1, _) = sampleMissionWithTwoRosterSlots()
        let aid = UUID()
        let row = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "S1",
            attachedDevice: "CALL1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        run.unitTestingReplaceOperatorLaunchPoses([aid: dummySimState()])
        XCTAssertNotNil(run.operatorLaunchPoseByAssignmentID[aid])

        run.updateTemplate(nil)

        XCTAssertTrue(run.operatorLaunchPoseByAssignmentID.isEmpty)
    }

    func test_updateTemplate_nil_clears_reserve_pool_sim_snapshots() {
        let (mission, task, _, _) = sampleMissionWithTwoRosterSlots()
        let slotID = UUID()
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        run.setReservePool(
            MissionRunReservePool(entries: [MissionRunReservePoolSlot(id: slotID, label: "P1", attachedDevice: "X")]),
            forTaskID: task.id
        )
        let snap = dummySimState()
        run.unitTestingReplaceReservePoolSimStartPoseSnapshots([slotID: snap])
        XCTAssertEqual(run.reservePoolSimStartPoseSnapshotBySlotID[slotID], snap)

        run.updateTemplate(nil)

        XCTAssertTrue(run.reservePoolSimStartPoseSnapshotBySlotID.isEmpty)
    }

    func test_clearReservePoolSimStartPoseSnapshots_drops_listed_slots() {
        let (mission, task, _, _) = sampleMissionWithTwoRosterSlots()
        let slot1 = UUID()
        let slot2 = UUID()
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: slot1, label: "A", attachedDevice: "d1"),
                MissionRunReservePoolSlot(id: slot2, label: "B", attachedDevice: "d2"),
            ]),
            forTaskID: task.id
        )
        let s1 = dummySimState()
        var s2 = dummySimState()
        s2.latitudeDeg = 9
        run.unitTestingReplaceReservePoolSimStartPoseSnapshots([slot1: s1, slot2: s2])

        run.clearReservePoolSimStartPoseSnapshots(forSlotIDs: [slot1])

        XCTAssertEqual(run.reservePoolSimStartPoseSnapshotBySlotID.count, 1)
        XCTAssertEqual(run.reservePoolSimStartPoseSnapshotBySlotID[slot2], s2)
    }

    func test_refreshDerivedTaskStates_prunes_snapshots_for_removed_assignments() {
        let (mission, task, rd1, rd2) = sampleMissionWithTwoRosterSlots()
        let aid1 = UUID()
        let aid2 = UUID()
        let orphan = UUID()
        let a1 = MissionRunAssignment(
            id: aid1,
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "S1",
            attachedDevice: "CALL1"
        )
        let a2 = MissionRunAssignment(
            id: aid2,
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "S2",
            attachedDevice: "CALL2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        let snap = dummySimState()
        run.unitTestingReplaceRosterSimStartPoseSnapshots([aid1: snap, aid2: snap, orphan: snap])

        run.assignments = [a1]
        run.refreshDerivedTaskStates()

        XCTAssertEqual(run.rosterSimStartPoseSnapshotByAssignmentID.count, 1)
        XCTAssertNotNil(run.rosterSimStartPoseSnapshotByAssignmentID[aid1])
        XCTAssertNil(run.rosterSimStartPoseSnapshotByAssignmentID[aid2])
        XCTAssertNil(run.rosterSimStartPoseSnapshotByAssignmentID[orphan])
    }

    func test_refreshDerivedTaskStates_prunes_reserve_pool_sim_snapshots_orphans() {
        let (mission, task, _, _) = sampleMissionWithTwoRosterSlots()
        let slotID = UUID()
        let orphan = UUID()
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        run.setReservePool(
            MissionRunReservePool(entries: [MissionRunReservePoolSlot(id: slotID, label: "P1", attachedDevice: "X")]),
            forTaskID: task.id
        )
        let s1 = dummySimState()
        var s2 = dummySimState()
        s2.latitudeDeg = 7
        run.unitTestingReplaceReservePoolSimStartPoseSnapshots([slotID: s1, orphan: s2])
        run.refreshDerivedTaskStates()
        XCTAssertEqual(run.reservePoolSimStartPoseSnapshotBySlotID[slotID], s1)
        XCTAssertNil(run.reservePoolSimStartPoseSnapshotBySlotID[orphan])
    }

    func test_clearRosterSimStartPoseSnapshots_drops_listed_rows() {
        let (mission, task, rd1, rd2) = sampleMissionWithTwoRosterSlots()
        let aid1 = UUID()
        let aid2 = UUID()
        let a1 = MissionRunAssignment(
            id: aid1,
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "S1",
            attachedDevice: "CALL1"
        )
        let a2 = MissionRunAssignment(
            id: aid2,
            taskId: task.id,
            rosterDeviceId: rd2,
            slotName: "S2",
            attachedDevice: "CALL2"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [a1, a2])
        let s1 = dummySimState()
        var s2 = dummySimState()
        s2.latitudeDeg = 9
        run.unitTestingReplaceRosterSimStartPoseSnapshots([aid1: s1, aid2: s2])

        run.clearRosterSimStartPoseSnapshots(forAssignmentIDs: [aid1])

        XCTAssertEqual(run.rosterSimStartPoseSnapshotByAssignmentID.count, 1)
        XCTAssertEqual(run.rosterSimStartPoseSnapshotByAssignmentID[aid2], s2)
    }

    func test_clearRosterSimStartPoseSnapshots_empty_ids_is_noop() {
        let (mission, task, rd1, _) = sampleMissionWithTwoRosterSlots()
        let aid = UUID()
        let row = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: rd1,
            slotName: "S1",
            attachedDevice: "CALL1"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [row])
        let snap = dummySimState()
        run.unitTestingReplaceRosterSimStartPoseSnapshots([aid: snap])

        run.clearRosterSimStartPoseSnapshots(forAssignmentIDs: [])

        XCTAssertEqual(run.rosterSimStartPoseSnapshotByAssignmentID[aid], snap)
    }

    func test_setReservePool_prunes_reserve_pool_sim_snapshots_removed_slots() {
        let (mission, task, _, _) = sampleMissionWithTwoRosterSlots()
        let idKeep = UUID()
        let idDrop = UUID()
        let run = MissionRunEnvironment(mission: mission, assignments: [])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: idKeep, label: "A", attachedDevice: "d1"),
                MissionRunReservePoolSlot(id: idDrop, label: "B", attachedDevice: "d2"),
            ]),
            forTaskID: task.id
        )
        let s1 = dummySimState()
        var s2 = dummySimState()
        s2.latitudeDeg = 8
        run.unitTestingReplaceReservePoolSimStartPoseSnapshots([idKeep: s1, idDrop: s2])

        run.setReservePool(
            MissionRunReservePool(entries: [MissionRunReservePoolSlot(id: idKeep, label: "A", attachedDevice: "d1")]),
            forTaskID: task.id
        )

        XCTAssertEqual(run.reservePoolSimStartPoseSnapshotBySlotID[idKeep], s1)
        XCTAssertNil(run.reservePoolSimStartPoseSnapshotBySlotID[idDrop])
    }
}

import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunFixedRosterReserveSwapTests: XCTestCase {

    private func sampleMission(primaryName: String = "Lead", reserveName: String = "Reserve One") -> Mission {
        let tid = UUID()
        let primaryDevice = RosterDevice(name: primaryName, role: .none, slot: .primary)
        let reserveDevice = RosterDevice(name: reserveName, role: .none, slot: .reserve)
        let task = MissionTask(
            id: tid,
            name: "Alpha",
            enabled: true,
            rosterDeviceIds: [primaryDevice.id, reserveDevice.id]
        )
        let routeMacro = RouteMacro(tasks: [task])
        return Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [primaryDevice, reserveDevice],
            routeMacro: routeMacro
        )
    }

    func test_swap_success_exchangesFleetTokens() {
        let mission = sampleMission()
        let tid = mission.routeMacro.tasks[0].id
        let primaryDevice = mission.rosterDevices.first { $0.slot == .primary }!
        let reserveDevice = mission.rosterDevices.first { $0.slot == .reserve }!

        let primaryAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: primaryDevice.id,
            slotName: primaryDevice.name,
            attachedFleetVehicleToken: "fleet:sim:alpha",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(
                commanded: .policySucceeded,
                observed: .policySucceeded
            )
        )
        let reserveAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: reserveDevice.id,
            slotName: reserveDevice.name,
            attachedFleetVehicleToken: "fleet:sim:bravo",
            slotLifecycleLanes: MissionRunAssignmentSlotStateLanes(
                commanded: .executingMission,
                observed: .executingMission
            )
        )
        let run = MissionRunEnvironment(
            missionId: mission.id,
            missionName: mission.name,
            assignments: [primaryAssignment, reserveAssignment]
        )
        run.updateTemplate(mission)

        let outcome = run.swapRosterVacancyWithFixedTemplateReserveAssignment(
            vacancyAssignmentID: primaryAssignment.id,
            reserveAssignmentID: reserveAssignment.id,
            taskID: tid,
            triggerSource: "test.fixedRosterSwap"
        )
        XCTAssertEqual(outcome, .success)

        let p = run.assignments.first { $0.id == primaryAssignment.id }!
        let r = run.assignments.first { $0.id == reserveAssignment.id }!
        XCTAssertEqual(p.attachedFleetVehicleToken, "fleet:sim:bravo")
        XCTAssertEqual(r.attachedFleetVehicleToken, "fleet:sim:alpha")
        XCTAssertNil(p.slotLifecycleLanes)
        XCTAssertNil(r.slotLifecycleLanes)

        let keys = run.events.compactMap(\.templateKey)
        XCTAssertTrue(keys.contains(MissionRunLogTemplateKey.fixedRosterReserveSwapEngaged))
        XCTAssertTrue(keys.contains(MissionRunReserveSwapPhaseLogTemplateKey.templateKey(phase: .rosterCommit, passed: true)))
    }

    func test_swap_blockedBySessionPhase_when_run_in_recovery() {
        let mission = sampleMission()
        let tid = mission.routeMacro.tasks[0].id
        let primaryDevice = mission.rosterDevices.first { $0.slot == .primary }!
        let reserveDevice = mission.rosterDevices.first { $0.slot == .reserve }!

        let primaryAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: primaryDevice.id,
            slotName: primaryDevice.name,
            attachedFleetVehicleToken: "fleet:sim:alpha"
        )
        let reserveAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: reserveDevice.id,
            slotName: reserveDevice.name,
            attachedFleetVehicleToken: "fleet:sim:bravo"
        )
        let run = MissionRunEnvironment(
            missionId: mission.id,
            missionName: mission.name,
            assignments: [primaryAssignment, reserveAssignment]
        )
        run.updateTemplate(mission)
        run.setSessionPhase(.aborting)

        let outcome = run.swapRosterVacancyWithFixedTemplateReserveAssignment(
            vacancyAssignmentID: primaryAssignment.id,
            reserveAssignmentID: reserveAssignment.id,
            taskID: tid,
            triggerSource: "test.fixedRosterSwap.blockedPhase"
        )
        XCTAssertEqual(outcome, .blockedBySessionPhase)
        let p = run.assignments.first { $0.id == primaryAssignment.id }!
        let r = run.assignments.first { $0.id == reserveAssignment.id }!
        XCTAssertEqual(p.attachedFleetVehicleToken, "fleet:sim:alpha")
        XCTAssertEqual(r.attachedFleetVehicleToken, "fleet:sim:bravo")
    }

    func test_swap_reserveNotEligible_whenReserveIsWingman() {
        let tid = UUID()
        let primaryDevice = RosterDevice(name: "Lead", role: .none, slot: .primary)
        let wing = RosterDevice(name: "Wing", role: .none, slot: .wingman, leaderRosterDeviceId: primaryDevice.id)
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [primaryDevice, wing],
            routeMacro: RouteMacro(tasks: [
                MissionTask(id: tid, name: "Alpha", enabled: true, rosterDeviceIds: [primaryDevice.id, wing.id]),
            ])
        )
        let primaryAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: primaryDevice.id,
            slotName: primaryDevice.name,
            attachedFleetVehicleToken: "fleet:sim:alpha"
        )
        let wingAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: wing.id,
            slotName: wing.name,
            attachedFleetVehicleToken: "fleet:sim:charlie"
        )
        let run = MissionRunEnvironment(
            missionId: mission.id,
            missionName: mission.name,
            assignments: [primaryAssignment, wingAssignment]
        )
        run.updateTemplate(mission)

        let outcome = run.swapRosterVacancyWithFixedTemplateReserveAssignment(
            vacancyAssignmentID: primaryAssignment.id,
            reserveAssignmentID: wingAssignment.id,
            taskID: tid,
            triggerSource: "test"
        )
        XCTAssertEqual(outcome, .reserveNotEligibleForVacancy)
    }

    func test_swap_assignmentNotBoundToTask_whenTaskIdMismatch() {
        let mission = sampleMission()
        let tid = mission.routeMacro.tasks[0].id
        let otherTask = UUID()
        let primaryDevice = mission.rosterDevices.first { $0.slot == .primary }!
        let reserveDevice = mission.rosterDevices.first { $0.slot == .reserve }!

        let primaryAssignment = MissionRunAssignment(
            taskId: tid,
            rosterDeviceId: primaryDevice.id,
            slotName: primaryDevice.name,
            attachedFleetVehicleToken: "fleet:sim:alpha"
        )
        let reserveAssignment = MissionRunAssignment(
            taskId: otherTask,
            rosterDeviceId: reserveDevice.id,
            slotName: reserveDevice.name,
            attachedFleetVehicleToken: "fleet:sim:bravo"
        )
        let run = MissionRunEnvironment(
            missionId: mission.id,
            missionName: mission.name,
            assignments: [primaryAssignment, reserveAssignment]
        )
        run.updateTemplate(mission)

        let outcome = run.swapRosterVacancyWithFixedTemplateReserveAssignment(
            vacancyAssignmentID: primaryAssignment.id,
            reserveAssignmentID: reserveAssignment.id,
            taskID: tid,
            triggerSource: "test"
        )
        XCTAssertEqual(outcome, .assignmentNotBoundToTask)
    }
}

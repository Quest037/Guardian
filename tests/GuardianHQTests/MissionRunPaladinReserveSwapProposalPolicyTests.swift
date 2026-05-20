import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunPaladinReserveSwapProposalPolicyTests: XCTestCase {

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

    func test_evaluate_success_primaryAndReserve() {
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

        let result = MissionRunPaladinReserveSwapProposalPolicy.evaluate(
            run: run,
            mission: mission,
            primaryAssignmentID: primaryAssignment.id,
            reserveAssignmentID: reserveAssignment.id
        )
        guard case .success(let payload) = result else {
            return XCTFail("Expected success, got \(result)")
        }
        XCTAssertEqual(payload.task.id, tid)
        XCTAssertEqual(payload.primary.id, primaryAssignment.id)
        XCTAssertEqual(payload.reserve.id, reserveAssignment.id)
    }

    func test_evaluate_failure_whenReserveNotTemplateReserve() {
        let tid = UUID()
        let primaryDevice = RosterDevice(name: "Lead", role: .none, slot: .primary)
        let wing = RosterDevice(name: "Wing", role: .none, slot: .wingman, leaderRosterDeviceId: primaryDevice.id)
        let task = MissionTask(
            id: tid,
            name: "Alpha",
            enabled: true,
            rosterDeviceIds: [primaryDevice.id, wing.id]
        )
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [primaryDevice, wing],
            routeMacro: RouteMacro(tasks: [task])
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

        let result = MissionRunPaladinReserveSwapProposalPolicy.evaluate(
            run: run,
            mission: mission,
            primaryAssignmentID: primaryAssignment.id,
            reserveAssignmentID: wingAssignment.id
        )
        guard case .failure(let failure) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(failure, .reserveNotTemplateReserveRow)
    }

    func test_evaluate_failure_whenSessionPhaseBlocksReserveSwap() {
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
        run.setSessionPhase(.recovery)

        let result = MissionRunPaladinReserveSwapProposalPolicy.evaluate(
            run: run,
            mission: mission,
            primaryAssignmentID: primaryAssignment.id,
            reserveAssignmentID: reserveAssignment.id
        )
        guard case .failure(let failure) = result else {
            return XCTFail("Expected failure, got \(result)")
        }
        XCTAssertEqual(failure, .reserveSwapBlockedBySessionPhase)
    }
}


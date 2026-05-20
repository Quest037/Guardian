import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunSkipTaskStartDeferralTests: XCTestCase {

    /// ``skipMissionTaskStartDeferral`` must clear MAVLink start deferral after dispatch (same as timer expiry), without pre-clearing it (which briefly broke derived task state for continuous-with-delay).
    func test_skip_clears_deferral_when_dispatch_context_exists() {
        let rd = UUID()
        let task = MissionTask(
            name: "Loop",
            cycles: 0,
            regularity: .continuousWithDelay,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    taskId: task.id,
                    rosterDeviceId: rd,
                    slotName: "Primary",
                    attachedFleetVehicleToken: "tokenPrimary"
                )
            ]
        )
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        run.captureExecutionContext(
            MissionRunExecutionContext(
                mission: mission,
                fleetLink: fleet,
                sitl: sitl,
                missionProvider: { mission }
            )
        )
        let future = Date().addingTimeInterval(120)
        run.systems.scheduling.setTaskStartDeferral(
            MissionTaskStartDeferral(startAt: future, totalDelay: 120),
            forTaskID: task.id
        )
        XCTAssertNotNil(run.taskStartDeferralByTaskID[task.id])
        XCTAssertEqual(run.taskStateByTaskID[task.id], .staging)

        run.systems.scheduling.skipMissionTaskStartDeferral(taskID: task.id)

        XCTAssertNil(run.taskStartDeferralByTaskID[task.id])
    }

    /// If dispatch cannot run, the operator must not be left with a deferral record and no timer.
    func test_skip_clears_deferral_when_no_execution_context() {
        let rd = UUID()
        let task = MissionTask(
            name: "Loop",
            cycles: 0,
            regularity: .continuousWithDelay,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    taskId: task.id,
                    rosterDeviceId: rd,
                    slotName: "Primary"
                )
            ]
        )
        run.status = .running
        run.setSessionPhase(.executing)
        run.systems.scheduling.setTaskStartDeferral(
            MissionTaskStartDeferral(startAt: Date().addingTimeInterval(60), totalDelay: 60),
            forTaskID: task.id
        )
        XCTAssertNotNil(run.taskStartDeferralByTaskID[task.id])

        run.systems.scheduling.skipMissionTaskStartDeferral(taskID: task.id)

        XCTAssertNil(run.taskStartDeferralByTaskID[task.id])
    }

    /// Rescheduling with a later ``startAt`` must cancel only the waiter and replace the deferral snapshot — not run ``cancelScheduledTaskMissionStarts`` (which cleared deferral before the new snapshot and broke derived task state).
    func test_adjust_positive_delta_reschedules_deferral_snapshot() {
        let rd = UUID()
        let task = MissionTask(
            name: "Loop",
            cycles: 0,
            regularity: .continuousWithDelay,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    taskId: task.id,
                    rosterDeviceId: rd,
                    slotName: "Primary",
                    attachedFleetVehicleToken: "tokenPrimary"
                )
            ]
        )
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        run.captureExecutionContext(
            MissionRunExecutionContext(
                mission: mission,
                fleetLink: fleet,
                sitl: sitl,
                missionProvider: { mission }
            )
        )
        let startAt = Date().addingTimeInterval(200)
        run.systems.scheduling.setTaskStartDeferral(
            MissionTaskStartDeferral(startAt: startAt, totalDelay: 200),
            forTaskID: task.id
        )
        run.systems.scheduling.adjustMissionTaskStartDeferralBySeconds(
            taskID: task.id,
            deltaSeconds: 30,
            referenceNow: Date()
        )
        guard let def = run.taskStartDeferralByTaskID[task.id] else {
            XCTFail("expected deferral after reschedule")
            return
        }
        XCTAssertEqual(def.totalDelay, 230, accuracy: 0.01)
        XCTAssertEqual(def.startAt.timeIntervalSince1970, startAt.addingTimeInterval(30).timeIntervalSince1970, accuracy: 2)
    }

    func test_adjust_negative_delta_past_now_triggers_skip_and_clears_deferral() {
        let rd = UUID()
        let task = MissionTask(
            name: "Loop",
            cycles: 0,
            regularity: .continuousWithDelay,
            rosterDeviceIds: [rd]
        )
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    taskId: task.id,
                    rosterDeviceId: rd,
                    slotName: "Primary",
                    attachedFleetVehicleToken: "tokenPrimary"
                )
            ]
        )
        run.attachServices(fleetLink: fleet, sitl: sitl)
        run.status = .running
        run.setSessionPhase(.executing)
        run.captureExecutionContext(
            MissionRunExecutionContext(
                mission: mission,
                fleetLink: fleet,
                sitl: sitl,
                missionProvider: { mission }
            )
        )
        run.systems.scheduling.setTaskStartDeferral(
            MissionTaskStartDeferral(startAt: Date().addingTimeInterval(45), totalDelay: 45),
            forTaskID: task.id
        )
        run.systems.scheduling.adjustMissionTaskStartDeferralBySeconds(
            taskID: task.id,
            deltaSeconds: -120,
            referenceNow: Date()
        )
        XCTAssertNil(run.taskStartDeferralByTaskID[task.id])
    }
}

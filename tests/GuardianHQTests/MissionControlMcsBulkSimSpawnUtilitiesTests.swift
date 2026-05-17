import XCTest
@testable import GuardianHQ

@MainActor
final class MissionControlMcsBulkSimSpawnUtilitiesTests: XCTestCase {
    func test_emptyReservePoolSlotCount_counts_unbound_berths_only() {
        let run = MissionRunEnvironment(missionId: UUID(), missionName: "T", assignments: [])
        let tid = UUID()
        run.appendReservePoolSlot(MissionRunReservePoolSlot(label: "A"), forTaskID: tid)
        run.appendReservePoolSlot(
            MissionRunReservePoolSlot(label: "B", attachedFleetVehicleToken: "sitl:1", attachedDevice: "sim"),
            forTaskID: tid
        )
        XCTAssertEqual(MissionControlMcsBulkSimSpawnUtilities.emptyReservePoolSlotCount(run: run, taskID: tid), 1)
    }

    func test_emptyReservePoolSlotCountAcrossMission_sums_tasks() {
        let run = MissionRunEnvironment(missionId: UUID(), missionName: "T", assignments: [])
        let t1 = UUID()
        let t2 = UUID()
        run.appendReservePoolSlot(MissionRunReservePoolSlot(label: "R1"), forTaskID: t1)
        run.appendReservePoolSlot(MissionRunReservePoolSlot(label: "R2"), forTaskID: t2)
        run.appendReservePoolSlot(MissionRunReservePoolSlot(label: "R3"), forTaskID: t2)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [
                MissionTask(id: t1, name: "A", rosterDeviceIds: []),
                MissionTask(id: t2, name: "B", rosterDeviceIds: []),
            ])
        )
        XCTAssertEqual(
            MissionControlMcsBulkSimSpawnUtilities.emptyReservePoolSlotCountAcrossMission(run: run, mission: mission),
            3
        )
    }

    func test_builtInSimulationPresetForTaskReservePoolBulkSpawn_uses_first_typed_roster_class() {
        let ugv = RosterDevice(name: "Rover", vehicleClass: .ugvWheeled)
        let copter = RosterDevice(name: "Drone", vehicleClass: .uavCopter)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [ugv, copter],
            routeMacro: RouteMacro(tasks: [
                MissionTask(name: "T", rosterDeviceIds: [ugv.id, copter.id]),
            ])
        )
        let task = mission.routeMacro.tasks[0]
        XCTAssertEqual(
            MissionControlMcsBulkSimSpawnUtilities.builtInSimulationPresetForTaskReservePoolBulkSpawn(task: task, mission: mission),
            FleetVehicleType.ugvWheeled.builtInSimulationVehiclePreset
        )
    }

    func test_builtInSimulationPresetForTaskReservePoolBulkSpawn_unknown_roster_falls_back_to_multicopter() {
        let rd = RosterDevice(name: "Slot", vehicleClass: .unknown)
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [rd],
            routeMacro: RouteMacro(tasks: [
                MissionTask(name: "T", rosterDeviceIds: [rd.id]),
            ])
        )
        let task = mission.routeMacro.tasks[0]
        XCTAssertEqual(
            MissionControlMcsBulkSimSpawnUtilities.builtInSimulationPresetForTaskReservePoolBulkSpawn(task: task, mission: mission),
            SimulationVehiclePreset.uavMultirotor
        )
    }
}

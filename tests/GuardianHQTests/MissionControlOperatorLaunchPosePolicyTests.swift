import XCTest
@testable import GuardianCore

@MainActor
final class MissionControlOperatorLaunchPosePolicyTests: XCTestCase {

    private func sampleLaunch() -> FleetSimState {
        FleetSimState(
            latitudeDeg: -35.1,
            longitudeDeg: 149.2,
            absoluteAltitudeM: 580,
            yawDeg: 90,
            batteryVoltageV: nil,
            ardupilotSimBattCapAh: nil,
            px4SimBatDrain: nil
        )
    }

    func test_resolvedReturnToLaunchDispatch_usesMovePointParkWhenLaunchCaptured() {
        let aid = UUID()
        let dispatch = MissionControlOperatorLaunchPosePolicy.resolvedReturnToLaunchDispatch(
            assignmentID: aid,
            launchPoseByAssignmentID: [aid: sampleLaunch()],
            planningRelativeAltitudeM: 42
        )
        guard case .recipe(let name, let params) = dispatch else {
            XCTFail("expected move+park recipe")
            return
        }
        XCTAssertEqual(name, FleetMovePointParkRecipeRegistrations.movePointParkRecipeName)
        XCTAssertEqual(params.double(named: "latitudeDeg"), -35.1)
        XCTAssertEqual(params.double(named: "longitudeDeg"), 149.2)
        XCTAssertEqual(params.double(named: "relativeAltitudeM"), 42)
        XCTAssertEqual(
            params.string(named: "procedureLogSummary"),
            MissionControlOperatorLaunchPosePolicy.returnToLaunchProcedureLogSummary
        )
    }

    func test_resolvedReturnToLaunchDispatch_fallsBackToStackRTLWithoutLaunch() {
        let dispatch = MissionControlOperatorLaunchPosePolicy.resolvedReturnToLaunchDispatch(
            assignmentID: UUID(),
            launchPoseByAssignmentID: [:],
            planningRelativeAltitudeM: 10
        )
        guard case .recipe(let name, _) = dispatch else {
            XCTFail("expected stack RTL recipe")
            return
        }
        XCTAssertEqual(name, FleetMissionRecipeRegistrations.doReturnHomeRecipeName)
    }

    func test_environment_returnToLaunchFleetDispatch_usesOperatorLaunch() {
        let (mission, task, rd1, _) = sampleMissionWithOneSlot()
        let aid = UUID()
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    id: aid,
                    taskId: task.id,
                    rosterDeviceId: rd1,
                    slotName: "S1",
                    attachedDevice: "CALL1"
                ),
            ]
        )
        run.unitTestingReplaceOperatorLaunchPoses([aid: sampleLaunch()])
        let dispatch = run.returnToLaunchFleetDispatch(
            assignment: run.assignments[0],
            mission: mission,
            planningHub: nil
        )
        guard case .recipe(let name, _) = dispatch else {
            XCTFail("expected recipe dispatch")
            return
        }
        XCTAssertEqual(name, FleetMovePointParkRecipeRegistrations.movePointParkRecipeName)
    }

    func test_clearOperatorLaunchPoses_dropsListedRows() {
        let (mission, task, rd1, _) = sampleMissionWithOneSlot()
        let aid = UUID()
        let run = MissionRunEnvironment(
            mission: mission,
            assignments: [
                MissionRunAssignment(
                    id: aid,
                    taskId: task.id,
                    rosterDeviceId: rd1,
                    slotName: "S1",
                    attachedDevice: "CALL1"
                ),
            ]
        )
        run.unitTestingReplaceOperatorLaunchPoses([aid: sampleLaunch()])
        run.clearOperatorLaunchPoses(forAssignmentIDs: [aid])
        XCTAssertTrue(run.operatorLaunchPoseByAssignmentID.isEmpty)
    }

    private func sampleMissionWithOneSlot() -> (mission: Mission, task: MissionTask, rd1: UUID, rd2: UUID) {
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
}

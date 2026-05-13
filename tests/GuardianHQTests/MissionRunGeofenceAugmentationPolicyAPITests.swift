import XCTest
@testable import GuardianHQ

@MainActor
final class MissionRunGeofenceAugmentationPolicyAPITests: XCTestCase {

    func test_updateMissionGeofenceAugmentation_setsAndClearsRunPolicies() {
        let task = MissionTask(name: "T")
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let cred = MissionRunPolicyEditCredential.localOperator(callsign: "OP")
        let fence = MissionGeofence.newCircle(name: "Aug", center: RouteCoordinate(lat: 1, lon: 2))
        XCTAssertTrue(run.updateMissionGeofenceAugmentation([fence], credential: cred).isAllowed)
        XCTAssertEqual(run.policies.missionGeofenceAugmentation.count, 1)
        XCTAssertTrue(run.updateMissionGeofenceAugmentation([], credential: cred).isAllowed)
        XCTAssertTrue(run.policies.missionGeofenceAugmentation.isEmpty)
    }

    func test_updateTaskGeofenceAugmentation_unknownTaskDenied() {
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [])
        )
        let run = MissionRunEnvironment(mission: mission)
        let cred = MissionRunPolicyEditCredential.localOperator(callsign: nil)
        let tid = UUID()
        let fence = MissionGeofence.newCircle(name: "X", center: RouteCoordinate(lat: 0, lon: 0))
        let d = run.updateTaskGeofenceAugmentation(taskID: tid, [fence], credential: cred)
        guard case .denied(let reason) = d else {
            XCTFail("expected denial")
            return
        }
        XCTAssertEqual(reason, .taskNotFound)
    }

    func test_updateTaskGeofenceAugmentation_clearRemovesDictionaryEntry() {
        let task = MissionTask(name: "T")
        let tid = task.id
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let cred = MissionRunPolicyEditCredential.localOperator(callsign: "A")
        let fence = MissionGeofence.newCircle(name: "Aug", center: RouteCoordinate(lat: 3, lon: 4))
        XCTAssertTrue(run.updateTaskGeofenceAugmentation(taskID: tid, [fence], credential: cred).isAllowed)
        XCTAssertEqual(run.taskGeofenceAugmentationsByTaskID[tid]?.count, 1)
        XCTAssertTrue(run.updateTaskGeofenceAugmentation(taskID: tid, [], credential: cred).isAllowed)
        XCTAssertNil(run.taskGeofenceAugmentationsByTaskID[tid])
    }

    func test_updateAssignmentGeofenceAugmentation_unknownAssignmentDenied() {
        let task = MissionTask(name: "T")
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let cred = MissionRunPolicyEditCredential.localOperator(callsign: "O")
        let aid = UUID()
        let fence = MissionGeofence.newCircle(name: "S", center: RouteCoordinate(lat: 1, lon: 1))
        let d = run.updateAssignmentGeofenceAugmentation(assignmentID: aid, [fence], credential: cred)
        guard case .denied(let reason) = d else {
            XCTFail("expected denial")
            return
        }
        XCTAssertEqual(reason, .assignmentNotFound)
    }

    func test_assistant_geofence_mutation_requiresGrant() {
        let task = MissionTask(name: "T")
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let cred = MissionRunPolicyEditCredential(issuer: .assistant, issuerKey: "x.ai", displayName: "AI")
        XCTAssertFalse(run.updateMissionGeofenceAugmentation([], credential: cred).isAllowed)
        run.systems.policyAuthority.grantPermission([.geofencePolicy], forIssuerKey: "x.ai")
        XCTAssertTrue(run.updateMissionGeofenceAugmentation([], credential: cred).isAllowed)
    }
}

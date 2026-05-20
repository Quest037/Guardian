import XCTest
@testable import GuardianCore

@MainActor
final class MissionRunGeofencePolicyResolutionTests: XCTestCase {

    func test_planningGeofences_additiveOrder() {
        let mFence = MissionGeofence.newCircle(name: "M", center: RouteCoordinate(lat: 1, lon: 1))
        var task = MissionTask(name: "T1")
        let tFence = MissionGeofence.newCircle(name: "T", center: RouteCoordinate(lat: 2, lon: 2))
        task.geofences = [tFence]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [mFence]
        )
        let runM = MissionGeofence.newCircle(name: "RunM", center: RouteCoordinate(lat: 3, lon: 3))
        let runT = MissionGeofence.newCircle(name: "RunT", center: RouteCoordinate(lat: 4, lon: 4))
        let merged = MissionRunGeofencePolicyResolution.planningGeofences(
            taskID: task.id,
            mission: mission,
            missionWideRunAugmentation: [runM],
            perTaskRunAugmentation: [runT]
        )
        XCTAssertEqual(merged.map(\.name), ["M", "T", "RunM", "RunT"])
    }

    func test_assignmentGeofences_matchesPlanningPlusSlotAugmentation() {
        let mFence = MissionGeofence.newCircle(name: "M", center: RouteCoordinate(lat: 0, lon: 0))
        var task = MissionTask(name: "T1")
        let tFence = MissionGeofence.newCircle(name: "T", center: RouteCoordinate(lat: 1, lon: 1))
        task.geofences = [tFence]
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [mFence]
        )
        let asn = MissionRunAssignment(
            id: UUID(),
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "Wing",
            policies: MissionRunAssignmentPolicies(
                geofenceAugmentation: [MissionGeofence.newCircle(name: "S", center: RouteCoordinate(lat: 9, lon: 9))]
            )
        )
        let merged = MissionRunGeofencePolicyResolution.assignmentGeofences(
            assignment: asn,
            mission: mission,
            missionWideRunAugmentation: [],
            perTaskRunAugmentationByTaskID: [:]
        )
        XCTAssertEqual(merged.map(\.name), ["M", "T", "S"])
    }

    func test_squadGeofences_appendsSlotAugmentation() {
        let mFence = MissionGeofence.newCircle(name: "M", center: RouteCoordinate(lat: 0, lon: 0))
        var task = MissionTask(name: "T1")
        task.geofences = []
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task]),
            missionGeofences: [mFence]
        )
        let aid = UUID()
        let rid = UUID()
        let asn = MissionRunAssignment(
            id: aid,
            taskId: task.id,
            rosterDeviceId: rid,
            slotName: "Primary",
            policies: MissionRunAssignmentPolicies(geofenceAugmentation: [MissionGeofence.newCircle(name: "S", center: RouteCoordinate(lat: 9, lon: 9))])
        )
        let squad = MissionRunGeofencePolicyResolution.squadGeofences(
            primaryAssignment: asn,
            mission: mission,
            missionWideRunAugmentation: [],
            perTaskRunAugmentationByTaskID: [:]
        )
        XCTAssertEqual(squad.count, 2)
        XCTAssertEqual(squad.last?.name, "S")
    }

    func test_assignment_policies_decode_emptyObject_hasEmptyGeofenceAugmentation() throws {
        let data = Data("{}".utf8)
        let p = try JSONDecoder().decode(MissionRunAssignmentPolicies.self, from: data)
        XCTAssertTrue(p.geofenceAugmentation.isEmpty)
    }

    func test_policyAuthority_assistant_requires_geofence_grant() {
        let auth = MissionRunPolicyAuthoritySubsystem()
        let cred = MissionRunPolicyEditCredential(issuer: .assistant, issuerKey: "test.assistant", displayName: "A")
        XCTAssertFalse(auth.canEdit(.missionGeofenceAugmentation, credential: cred))
        auth.grantPermission([.geofencePolicy], forIssuerKey: "test.assistant")
        XCTAssertTrue(auth.canEdit(.taskGeofenceAugmentation(taskID: UUID()), credential: cred))
    }
}

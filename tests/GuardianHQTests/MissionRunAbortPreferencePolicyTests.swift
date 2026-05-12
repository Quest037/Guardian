import XCTest
@testable import GuardianHQ

final class MissionRunAbortPreferencePolicyTests: XCTestCase {

    func test_normalizedPreferenceChain_appendsParkWhenMissing() {
        let input = [MissionRunAbortTactic(kind: .returnToLaunch)]
        let out = MissionRunAbortTactic.normalizedPreferenceChain(input)
        XCTAssertEqual(out.last?.kind, .park)
        XCTAssertEqual(out.first?.kind, .returnToLaunch)
    }

    func test_normalizedPreferenceChain_emptyUsesDefault() {
        let out = MissionRunAbortTactic.normalizedPreferenceChain([])
        XCTAssertFalse(out.isEmpty)
        XCTAssertEqual(out.last?.kind, .park)
    }

    func test_resolvedAbortPreferenceChain_assignmentOverridesTaskAndMission() {
        let taskID = UUID()
        let rosterID = UUID()
        var task = MissionTask(id: taskID, name: "Alpha")
        task.abortPreferenceChainOverride = [MissionRunAbortTactic(kind: .returnToLaunch)]

        var rules = RouteRules()
        rules.missionAbortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]

        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )

        var policies = MissionRunAssignmentPolicies()
        policies.abortPreferenceChain = [MissionRunAbortTactic(kind: .loiter)]

        let assignment = MissionRunAssignment(
            taskId: taskID,
            rosterDeviceId: rosterID,
            slotName: "P1",
            policies: policies
        )

        let resolved = MissionRunPolicyResolution.resolvedAbortPreferenceChain(assignment: assignment, mission: mission)
        XCTAssertEqual(resolved.first?.kind, .loiter)
    }

    func test_inheritedAbortPreferenceChainForSlot_ignoresSlotOverride() {
        let taskID = UUID()
        let rosterID = UUID()
        var task = MissionTask(id: taskID, name: "Alpha")
        task.abortPreferenceChainOverride = [MissionRunAbortTactic(kind: .loiter)]

        var rules = RouteRules()
        rules.missionAbortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]

        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )

        var policies = MissionRunAssignmentPolicies()
        policies.abortPreferenceChain = [MissionRunAbortTactic(kind: .returnToLaunch)]

        let assignment = MissionRunAssignment(
            taskId: taskID,
            rosterDeviceId: rosterID,
            slotName: "P1",
            policies: policies
        )

        let inherited = MissionRunPolicyResolution.inheritedAbortPreferenceChainForSlot(assignment: assignment, mission: mission)
        XCTAssertEqual(inherited.first?.kind, .loiter)
    }

    func test_routeRules_decodeWithoutAbortChainUsesDefaultWithTerminalPark() throws {
        let json = """
        {"defaultSpeed":5,"defaultHeadingHold":true}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let rules = try JSONDecoder().decode(RouteRules.self, from: data)
        XCTAssertEqual(rules.missionAbortPreferenceChain.last?.kind, .park)
        XCTAssertEqual(rules.missionCompletePreferenceChain.last?.kind, .park)
    }

    func test_abortTactic_decodeNearestOpenDefaultsMapKindToRally() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"nearestOpenMapPoint"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let tactic = try JSONDecoder().decode(MissionRunAbortTactic.self, from: data)
        XCTAssertEqual(tactic.kind, .nearestOpenMapPoint)
        XCTAssertEqual(tactic.mapPointKind, .rally)
    }

    func test_abortTactic_decodeHoldPositionMigratesToLoiter() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"holdPosition"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let tactic = try JSONDecoder().decode(MissionRunAbortTactic.self, from: data)
        XCTAssertEqual(tactic.kind, .loiter)
    }

    func test_abortTactic_decodeLandMigratesToReturnToLaunch() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"land"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let tactic = try JSONDecoder().decode(MissionRunAbortTactic.self, from: data)
        XCTAssertEqual(tactic.kind, .returnToLaunch)
    }

    func test_abortTactic_setupMenuLabel_nearestOpenMissionPoint() {
        let t = MissionRunAbortTactic(kind: .nearestOpenMapPoint, mapPointKind: .extraction)
        XCTAssertEqual(t.setupMenuLabel, "Nearest open mission point")
    }

    func test_completeTactic_decodeHoldPositionMigratesToLoiter() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"holdPosition"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let tactic = try JSONDecoder().decode(MissionRunCompleteTactic.self, from: data)
        XCTAssertEqual(tactic.kind, .loiter)
    }

    func test_completeTactic_decodeLandMigratesToReturnToLaunch() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","kind":"land"}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let tactic = try JSONDecoder().decode(MissionRunCompleteTactic.self, from: data)
        XCTAssertEqual(tactic.kind, .returnToLaunch)
    }

    func test_normalizedCompletePreferenceChain_singleNoneStaysAlone() {
        let input = [MissionRunCompleteTactic(kind: .none)]
        let out = MissionRunCompleteTactic.normalizedPreferenceChain(input)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].kind, .none)
    }

    func test_resolvedCompletePreferenceChain_assignmentOverridesTask() {
        let taskID = UUID()
        let rosterID = UUID()
        var task = MissionTask(id: taskID, name: "Alpha")
        task.completePreferenceChainOverride = [MissionRunCompleteTactic(kind: .returnToLaunch)]

        var rules = RouteRules()
        rules.missionCompletePreferenceChain = [MissionRunCompleteTactic(kind: .returnToLaunch)]

        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )

        var policies = MissionRunAssignmentPolicies()
        policies.completePreferenceChain = [MissionRunCompleteTactic(kind: .loiter)]

        let assignment = MissionRunAssignment(
            taskId: taskID,
            rosterDeviceId: rosterID,
            slotName: "P1",
            policies: policies
        )

        let resolved = MissionRunPolicyResolution.resolvedCompletePreferenceChain(assignment: assignment, mission: mission)
        XCTAssertEqual(resolved.first?.kind, .loiter)
    }
}

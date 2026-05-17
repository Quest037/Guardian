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
        XCTAssertEqual(rules.missionReserveSwapPreferenceChain.last?.kind, .park)
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

    func test_defaultMissionCompletePreferenceChain_extractionThenRTLThenPark() {
        let chain = MissionRunCompleteTactic.defaultMissionCompletePreferenceChain
        XCTAssertEqual(chain.count, 3)
        XCTAssertEqual(chain[0].kind, .nearestOpenMapPoint)
        XCTAssertEqual(chain[0].mapPointKind, .extraction)
        XCTAssertEqual(chain[1].kind, .returnToLaunch)
        XCTAssertEqual(chain[2].kind, .park)
    }

    func test_normalizedCompletePreferenceChain_emptyUsesDefaultExtractionRTLChain() {
        let out = MissionRunCompleteTactic.normalizedPreferenceChain([])
        XCTAssertEqual(out, MissionRunCompleteTactic.defaultMissionCompletePreferenceChain)
    }

    func test_upgradingStoredMissionWideChain_replaces_superseded_rtl_park_default() {
        let legacy = MissionRunCompleteTactic.supersededMissionCompletePreferenceChain
        XCTAssertTrue(MissionRunCompleteTactic.isSupersededMissionWideCompleteChain(legacy))
        let upgraded = MissionRunCompleteTactic.upgradingStoredMissionWideChain(legacy)
        XCTAssertEqual(upgraded.count, 3)
        XCTAssertEqual(upgraded[0].kind, .nearestOpenMapPoint)
        XCTAssertEqual(upgraded[0].mapPointKind, .extraction)
        XCTAssertEqual(upgraded[1].kind, .returnToLaunch)
        XCTAssertEqual(upgraded[2].kind, .park)
    }

    func test_upgradingStoredMissionWideChain_preserves_custom_chain() {
        let custom = [
            MissionRunCompleteTactic(kind: .loiter),
            MissionRunCompleteTactic(kind: .park),
        ]
        let out = MissionRunCompleteTactic.upgradingStoredMissionWideChain(custom)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].kind, .loiter)
        XCTAssertEqual(out[1].kind, .park)
    }

    func test_routeRules_decode_upgrades_legacy_complete_default() throws {
        let json = """
        {
          "defaultSpeed": 5,
          "defaultHeadingHold": true,
          "missionCompletePreferenceChain": [
            {"id":"00000000-0000-0000-0000-000000000001","kind":"returnToLaunch"},
            {"id":"00000000-0000-0000-0000-000000000002","kind":"park"}
          ]
        }
        """
        let rules = try JSONDecoder().decode(RouteRules.self, from: Data(json.utf8))
        XCTAssertEqual(rules.missionCompletePreferenceChain.count, 3)
        XCTAssertEqual(rules.missionCompletePreferenceChain[0].kind, .nearestOpenMapPoint)
        XCTAssertEqual(rules.missionCompletePreferenceChain[0].mapPointKind, .extraction)
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

    func test_normalizedReserveSwapPreferenceChain_singleNoneStaysAlone() {
        let input = [MissionRunReserveSwapTactic(kind: .none)]
        let out = MissionRunReserveSwapTactic.normalizedPreferenceChain(input)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].kind, .none)
    }

    func test_resolvedReserveSwapPreferenceChain_assignmentOverridesTask() {
        let taskID = UUID()
        let rosterID = UUID()
        var task = MissionTask(id: taskID, name: "Alpha")
        task.reserveSwapPreferenceChainOverride = [MissionRunReserveSwapTactic(kind: .returnToLaunch)]

        var rules = RouteRules()
        rules.missionReserveSwapPreferenceChain = [MissionRunReserveSwapTactic(kind: .returnToLaunch)]

        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )

        var policies = MissionRunAssignmentPolicies()
        policies.reserveSwapPreferenceChain = [MissionRunReserveSwapTactic(kind: .loiter)]

        let assignment = MissionRunAssignment(
            taskId: taskID,
            rosterDeviceId: rosterID,
            slotName: "P1",
            policies: policies
        )

        let resolved = MissionRunPolicyResolution.resolvedReserveSwapPreferenceChain(assignment: assignment, mission: mission)
        XCTAssertEqual(resolved.first?.kind, .loiter)
    }

    func test_inheritedReserveSwapPreferenceChainForSlot_ignoresSlotOverride() {
        let taskID = UUID()
        let rosterID = UUID()
        var task = MissionTask(id: taskID, name: "Alpha")
        task.reserveSwapPreferenceChainOverride = [MissionRunReserveSwapTactic(kind: .loiter)]

        var rules = RouteRules()
        rules.missionReserveSwapPreferenceChain = [MissionRunReserveSwapTactic(kind: .returnToLaunch)]

        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )

        var policies = MissionRunAssignmentPolicies()
        policies.reserveSwapPreferenceChain = [MissionRunReserveSwapTactic(kind: .returnToLaunch)]

        let assignment = MissionRunAssignment(
            taskId: taskID,
            rosterDeviceId: rosterID,
            slotName: "P1",
            policies: policies
        )

        let inherited = MissionRunPolicyResolution.inheritedReserveSwapPreferenceChainForSlot(assignment: assignment, mission: mission)
        XCTAssertEqual(inherited.first?.kind, .loiter)
    }

    func test_missionTemplateReserveSwapPreferenceChain_ignoresOverrides() {
        let taskID = UUID()
        let rosterID = UUID()
        var task = MissionTask(id: taskID, name: "Alpha")
        task.reserveSwapPreferenceChainOverride = [MissionRunReserveSwapTactic(kind: .loiter)]

        var rules = RouteRules()
        rules.missionReserveSwapPreferenceChain = [MissionRunReserveSwapTactic(kind: .park)]

        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task], rules: rules)
        )

        let policies = MissionRunAssignmentPolicies()
        let assignment = MissionRunAssignment(
            taskId: taskID,
            rosterDeviceId: rosterID,
            slotName: "P1",
            policies: policies
        )

        let template = MissionRunPolicyResolution.missionTemplateReserveSwapPreferenceChain(mission: mission)
        XCTAssertEqual(template.first?.kind, .park)

        let resolved = MissionRunPolicyResolution.resolvedReserveSwapPreferenceChain(assignment: assignment, mission: mission)
        XCTAssertEqual(resolved.first?.kind, .loiter)
    }
}

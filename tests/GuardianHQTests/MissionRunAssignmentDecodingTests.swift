import XCTest
@testable import GuardianHQ

final class MissionRunAssignmentDecodingTests: XCTestCase {
    /// Older persisted runs may include `simStartOverrideCoord`; it is no longer modeled and must not break decode.
    func test_decode_ignoresLegacySimStartOverrideKey() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "rosterDeviceId": "22222222-2222-2222-2222-222222222222",
          "slotName": "Alpha",
          "attachedDevice": "",
          "simStartOverrideCoord": {"lat": -33.0, "lon": 151.0}
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MissionRunAssignment.self, from: data)
        XCTAssertEqual(decoded.slotName, "Alpha")
        XCTAssertEqual(decoded.id.uuidString, "11111111-1111-1111-1111-111111111111")
    }

    func test_decode_omitted_slotLifecycleLanes_defaults_nil_effective_idle() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "rosterDeviceId": "22222222-2222-2222-2222-222222222222",
          "slotName": "Alpha",
          "attachedDevice": ""
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(MissionRunAssignment.self, from: data)
        XCTAssertNil(decoded.slotLifecycleLanes)
        XCTAssertEqual(decoded.effectiveSlotLifecycleLanes.commanded, .idle)
        XCTAssertEqual(decoded.effectiveSlotLifecycleLanes.observed, .idle)
    }

    func test_roundTrip_preservesSlotLifecycleLanes() throws {
        let rosterId = UUID()
        let taskId = UUID()
        let lanes = MissionRunAssignmentSlotStateLanes(commanded: .policyAborting, observed: .executingMission)
        let original = MissionRunAssignment(
            taskId: taskId,
            rosterDeviceId: rosterId,
            slotName: "Primary",
            slotLifecycleLanes: lanes
        )
        let data = try JSONEncoder().encode(original)
        let roundTrip = try JSONDecoder().decode(MissionRunAssignment.self, from: data)
        XCTAssertEqual(roundTrip.slotLifecycleLanes, lanes)
        XCTAssertEqual(roundTrip.effectiveSlotLifecycleLanes, lanes)
    }

    /// Option **(a)** on-row storage: synthetic pool probe rows never carry persisted lanes; lifecycle writers target real roster rows.
    func test_synthetic_reserve_pool_row_has_nil_slot_lanes_effective_idle() {
        let slot = MissionRunReservePoolSlot(label: "P1", attachedFleetVehicleToken: "tok", attachedDevice: "")
        let synthetic = MissionRunAssignment.syntheticForReservePool(slot: slot)
        XCTAssertNil(synthetic.slotLifecycleLanes)
        XCTAssertEqual(synthetic.effectiveSlotLifecycleLanes.commanded, .idle)
        XCTAssertEqual(synthetic.effectiveSlotLifecycleLanes.observed, .idle)
    }

    func test_roundTrip_preservesAbortPolicyOverride() throws {
        let rosterId = UUID()
        let taskId = UUID()
        let tactic = MissionRunAbortTactic(kind: .park)
        let policies = MissionRunAssignmentPolicies(abortPreferenceChain: [tactic])
        let original = MissionRunAssignment(
            taskId: taskId,
            rosterDeviceId: rosterId,
            slotName: "Primary",
            policies: policies
        )
        let data = try JSONEncoder().encode(original)
        let roundTrip = try JSONDecoder().decode(MissionRunAssignment.self, from: data)
        XCTAssertEqual(roundTrip.id, original.id)
        XCTAssertEqual(roundTrip.taskId, taskId)
        let decodedChain = try XCTUnwrap(roundTrip.policies.abortPreferenceChain)
        XCTAssertEqual(decodedChain.count, 1)
        XCTAssertEqual(decodedChain[0].kind, .park)
    }

    func test_resolvedTaskId_nil_taskId_single_enabled_task() {
        let deviceId = UUID()
        let onlyTask = MissionTask(name: "Solo", rosterDeviceIds: [deviceId])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: deviceId, name: "Pilot")],
            routeMacro: RouteMacro(tasks: [onlyTask])
        )
        let assignment = MissionRunAssignment(taskId: nil, rosterDeviceId: deviceId, slotName: "Pilot")
        XCTAssertEqual(MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission), onlyTask.id)
    }

    func test_resolvedTaskId_nil_taskId_multiple_enabled_tasks_is_nil() {
        let d1 = UUID()
        let d2 = UUID()
        let t1 = MissionTask(name: "A", rosterDeviceIds: [d1])
        let t2 = MissionTask(name: "B", rosterDeviceIds: [d2])
        let mission = Mission(
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: d1, name: "P1"),
                RosterDevice(id: d2, name: "P2"),
            ],
            routeMacro: RouteMacro(tasks: [t1, t2])
        )
        let assignment = MissionRunAssignment(taskId: nil, rosterDeviceId: d1, slotName: "P1")
        XCTAssertNil(MissionRunPolicyResolution.resolvedTaskId(for: assignment, mission: mission))
    }
}

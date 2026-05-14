import Foundation
import XCTest

@testable import GuardianHQ

final class MissionRunReservePoolTests: XCTestCase {

    func test_slot_hasFleetOrLegacyBinding_when_token_or_device_nonempty() {
        let a = MissionRunReservePoolSlot(label: "R1", attachedFleetVehicleToken: "tok", attachedDevice: "")
        XCTAssertTrue(a.hasFleetOrLegacyBinding)
        let b = MissionRunReservePoolSlot(label: "R2", attachedFleetVehicleToken: nil, attachedDevice: "NOCALL")
        XCTAssertTrue(b.hasFleetOrLegacyBinding)
        let c = MissionRunReservePoolSlot(label: "R3", attachedFleetVehicleToken: nil, attachedDevice: "  ")
        XCTAssertFalse(c.hasFleetOrLegacyBinding)
    }

    func test_floating_reserve_mc_read_only_binding_display() {
        let empty = MissionRunReservePoolSlot(label: "E", attachedDevice: "  ")
        XCTAssertEqual(empty.floatingReserveMcReadOnlyBindingDisplay(resolvedFleetDisplayShortID: nil), "Empty")

        let legacy = MissionRunReservePoolSlot(label: "L", attachedDevice: "  CALL  ")
        XCTAssertEqual(legacy.floatingReserveMcReadOnlyBindingDisplay(resolvedFleetDisplayShortID: nil), "CALL")

        let fleet = MissionRunReservePoolSlot(label: "F", attachedFleetVehicleToken: "live", attachedDevice: "ignored")
        XCTAssertEqual(fleet.floatingReserveMcReadOnlyBindingDisplay(resolvedFleetDisplayShortID: "UAV-A:1"), "UAV-A:1")
        XCTAssertEqual(fleet.floatingReserveMcReadOnlyBindingDisplay(resolvedFleetDisplayShortID: nil), "ignored")

        let tokenOnly = MissionRunReservePoolSlot(label: "T", attachedFleetVehicleToken: "live", attachedDevice: "")
        XCTAssertEqual(tokenOnly.floatingReserveMcReadOnlyBindingDisplay(resolvedFleetDisplayShortID: nil), "Bound")
    }

    func test_reserve_pool_roundtrip_json() throws {
        let pool = MissionRunReservePool(entries: [
            MissionRunReservePoolSlot(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!,
                label: "A",
                attachedFleetVehicleToken: "v:1",
                attachedDevice: ""
            ),
        ])
        let data = try JSONEncoder().encode(pool)
        let decoded = try JSONDecoder().decode(MissionRunReservePool.self, from: data)
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].label, "A")
        XCTAssertEqual(decoded.entries[0].attachedFleetVehicleToken, "v:1")
        XCTAssertEqual(decoded.entries[0].id, UUID(uuidString: "00000000-0000-0000-0000-0000000000AA"))
    }

    /// Extra keys from older envelopes decode without failing; slot stays binding-only.
    func test_decode_legacy_json_extra_keys_ignored() throws {
        let json = """
        {"entries":[{"id":"00000000-0000-0000-0000-000000000003","label":"Legacy","attachedDevice":"bound","consumedAt":1000000}]}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(MissionRunReservePool.self, from: data)
        XCTAssertEqual(decoded.entries.count, 1)
        XCTAssertEqual(decoded.entries[0].label, "Legacy")
        XCTAssertEqual(decoded.entries[0].attachedDevice, "bound")
        XCTAssertTrue(decoded.entries[0].hasFleetOrLegacyBinding)
    }

    @MainActor
    func test_update_template_prunes_unknown_task_keys() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let stale = UUID()
        let live = task.id
        run.setReservePool(MissionRunReservePool(entries: [MissionRunReservePoolSlot(label: "x", attachedDevice: "d")]), forTaskID: stale)
        run.setReservePool(MissionRunReservePool(entries: [MissionRunReservePoolSlot(label: "y", attachedDevice: "e")]), forTaskID: live)
        run.updateTemplate(mission)
        XCTAssertNil(run.reservePoolByTaskID[stale])
        XCTAssertEqual(run.reservePoolByTaskID[live]?.entries.count, 1)
    }

    @MainActor
    func test_update_template_prunes_reserve_pool_bulk_sim_home_for_unknown_tasks() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let stale = UUID()
        let live = task.id
        run.setReservePoolBulkSimHome(RouteCoordinate(lat: 1, lon: 2), forTaskID: stale)
        run.setReservePoolBulkSimHome(RouteCoordinate(lat: 3, lon: 4), forTaskID: live)
        run.updateTemplate(mission)
        XCTAssertNil(run.reservePoolBulkSimHome(forTaskID: stale))
        XCTAssertEqual(run.reservePoolBulkSimHome(forTaskID: live)?.lat, 3)
        XCTAssertEqual(run.reservePoolBulkSimHome(forTaskID: live)?.lon, 4)
    }

    @MainActor
    func test_available_reserve_pool_entries_excludes_empty_slots() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "ok", attachedDevice: "bound"),
                MissionRunReservePoolSlot(label: "empty", attachedDevice: "   "),
            ]),
            forTaskID: tid
        )
        let avail = run.availableReservePoolEntries(forTaskID: tid)
        XCTAssertEqual(avail.count, 1)
        XCTAssertEqual(avail[0].label, "ok")
    }

    @MainActor
    func test_available_reserve_pool_entries_excludes_written_off_fleet_vehicle_on_run() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "ok", attachedFleetVehicleToken: "keep", attachedDevice: ""),
                MissionRunReservePoolSlot(label: "gone", attachedFleetVehicleToken: "lost", attachedDevice: ""),
            ]),
            forTaskID: tid
        )
        run.markFleetVehicleWrittenOffForReservePool(storageKey: "lost")
        let avail = run.availableReservePoolEntries(forTaskID: tid)
        XCTAssertEqual(avail.count, 1)
        XCTAssertEqual(avail[0].label, "ok")
        XCTAssertTrue(run.isFleetVehicleWrittenOffForReservePool(storageKey: "lost"))
        run.clearFleetVehicleWrittenOffForReservePool(storageKey: "lost")
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid).count, 2)
    }

    @MainActor
    func test_legacy_text_only_slot_not_excluded_by_fleet_written_off_set() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "legacy", attachedFleetVehicleToken: nil, attachedDevice: "CALL"),
            ]),
            forTaskID: tid
        )
        run.markFleetVehicleWrittenOffForReservePool(storageKey: "CALL")
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid).count, 1)
    }

    @MainActor
    func test_available_reserve_pool_entries_excludes_unresolved_fleet_when_services_attached() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let ghostSim = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    label: "ghost",
                    attachedFleetVehicleToken: "sitl:\(ghostSim.uuidString)",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid).count, 1)
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        run.attachServices(fleetLink: fleet, sitl: sitl)
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid).count, 0)
    }

    @MainActor
    func test_available_reserve_pool_entries_legacy_eligible_when_services_attached() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "leg", attachedFleetVehicleToken: nil, attachedDevice: "CALL"),
            ]),
            forTaskID: tid
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        run.attachServices(fleetLink: fleet, sitl: sitl)
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid).count, 1)
    }

    @MainActor
    func test_append_reserve_pool_slot_preserves_existing() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let first = MissionRunReservePoolSlot(label: "a", attachedDevice: "d1")
        run.setReservePool(MissionRunReservePool(entries: [first]), forTaskID: tid)
        let second = MissionRunReservePoolSlot(label: "b", attachedDevice: "d2")
        run.appendReservePoolSlot(second, forTaskID: tid)
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries.count, 2)
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries.map(\.label), ["a", "b"])
    }

    @MainActor
    func test_remove_reserve_pool_slot_drops_task_key_when_pool_empty() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let slot = MissionRunReservePoolSlot(label: "only", attachedDevice: "x")
        run.appendReservePoolSlot(slot, forTaskID: tid)
        XCTAssertTrue(run.removeReservePoolSlot(id: slot.id, forTaskID: tid))
        XCTAssertNil(run.reservePoolByTaskID[tid])
    }

    @MainActor
    func test_remove_reserve_pool_slot_unknown_id_returns_false() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        run.appendReservePoolSlot(MissionRunReservePoolSlot(label: "a", attachedDevice: "x"), forTaskID: tid)
        XCTAssertFalse(run.removeReservePoolSlot(id: UUID(), forTaskID: tid))
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries.count, 1)
    }

    @MainActor
    func test_replace_reserve_pool_slot_keeps_stable_id() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let stable = UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!
        let original = MissionRunReservePoolSlot(id: stable, label: "old", attachedDevice: "d0")
        run.appendReservePoolSlot(original, forTaskID: tid)
        let otherID = UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        let payload = MissionRunReservePoolSlot(
            id: otherID,
            label: "new",
            attachedFleetVehicleToken: "v:9",
            attachedDevice: ""
        )
        XCTAssertTrue(run.replaceReservePoolSlot(id: stable, forTaskID: tid, with: payload))
        let row = run.reservePool(forTaskID: tid).entries[0]
        XCTAssertEqual(row.id, stable)
        XCTAssertEqual(row.label, "new")
        XCTAssertEqual(row.attachedFleetVehicleToken, "v:9")
    }

    @MainActor
    func test_replace_reserve_pool_slot_unknown_id_returns_false() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        run.appendReservePoolSlot(MissionRunReservePoolSlot(label: "a", attachedDevice: "x"), forTaskID: tid)
        let bogus = MissionRunReservePoolSlot(label: "z", attachedDevice: "y")
        XCTAssertFalse(run.replaceReservePoolSlot(id: UUID(), forTaskID: tid, with: bogus))
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries[0].label, "a")
    }

    func test_apply_reserve_pool_return_payload_merges_matching_fleet_token() {
        let simUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let key = "sitl:\(simUUID.uuidString)"
        var pool = MissionRunReservePool(entries: [
            MissionRunReservePoolSlot(label: "old", attachedFleetVehicleToken: key, attachedDevice: ""),
        ])
        let stableID = pool.entries[0].id
        let payload = MissionRunReservePoolSlot(label: "new", attachedFleetVehicleToken: key, attachedDevice: "aux")
        let out = pool.applyReservePoolReturnPayload(payload, mergeFleetStorageKey: key)
        XCTAssertEqual(out, .mergedExisting(slotID: stableID))
        XCTAssertEqual(pool.entries.count, 1)
        XCTAssertEqual(pool.entries[0].label, "old")
        XCTAssertEqual(pool.entries[0].attachedDevice, "aux")
    }

    func test_apply_reserve_pool_return_payload_appends_when_no_merge_key() {
        let simUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        let key = "sitl:\(simUUID.uuidString)"
        var pool = MissionRunReservePool(entries: [
            MissionRunReservePoolSlot(label: "a", attachedFleetVehicleToken: key, attachedDevice: ""),
        ])
        let payload = MissionRunReservePoolSlot(label: "b", attachedFleetVehicleToken: key, attachedDevice: "")
        let out = pool.applyReservePoolReturnPayload(payload, mergeFleetStorageKey: nil)
        guard case .appended(let id) = out else {
            XCTFail("expected append")
            return
        }
        XCTAssertEqual(pool.entries.count, 2)
        XCTAssertEqual(pool.entries.last?.id, id)
    }

    func test_operational_reserve_pool_return_rejection_not_live() {
        let op = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: VehicleLifecycleStatus(stage: .stopped))
        XCTAssertEqual(
            op.reservePoolReturnFromAssignmentRejection(),
            .rejectedVehicleNotOperational(stage: .stopped)
        )
    }

    func test_operational_reserve_pool_return_rejection_battery_critical() {
        var hub = FleetHubVehicleTelemetry.empty
        hub.batteryRemainingPercent = 0.05
        let op = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: VehicleLifecycleStatus(stage: .live))
        XCTAssertEqual(op.reservePoolReturnFromAssignmentRejection(), .rejectedBatteryCritical)
    }

    func test_operational_reserve_pool_return_allows_live_unknown_battery() {
        let op = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: VehicleLifecycleStatus(stage: .live))
        XCTAssertNil(op.reservePoolReturnFromAssignmentRejection())
    }

    func test_operational_qualifies_for_reserve_pool_draw_matches_rejection() {
        let badLife = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: VehicleLifecycleStatus(stage: .stopped))
        XCTAssertFalse(badLife.qualifiesForMissionRunReservePoolOperationalDraw)
        var hub = FleetHubVehicleTelemetry.empty
        hub.batteryRemainingPercent = 0.05
        let badBatt = FleetVehicleOperationalModel(hub: hub, lifecycleStatus: VehicleLifecycleStatus(stage: .live))
        XCTAssertFalse(badBatt.qualifiesForMissionRunReservePoolOperationalDraw)
        let ok = FleetVehicleOperationalModel(hub: nil, lifecycleStatus: VehicleLifecycleStatus(stage: .live))
        XCTAssertTrue(ok.qualifiesForMissionRunReservePoolOperationalDraw)
    }

    @MainActor
    func test_return_assignment_legacy_appended() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let assignment = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "W1",
            attachedDevice: "NOCALL",
            attachedFleetVehicleToken: nil
        )
        let out = run.returnAssignmentToReservePool(assignment, forTaskID: tid)
        guard case .appended(let slotID) = out else {
            XCTFail("expected appended")
            return
        }
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries.count, 1)
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries[0].id, slotID)
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries[0].label, "Reserve 1")
    }

    @MainActor
    func test_return_assignment_legacy_appended_twice_two_slots() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let a1 = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "A", attachedDevice: "D1", attachedFleetVehicleToken: nil)
        let a2 = MissionRunAssignment(rosterDeviceId: UUID(), slotName: "B", attachedDevice: "D2", attachedFleetVehicleToken: nil)
        _ = run.returnAssignmentToReservePool(a1, forTaskID: tid)
        _ = run.returnAssignmentToReservePool(a2, forTaskID: tid)
        XCTAssertEqual(run.reservePool(forTaskID: tid).entries.count, 2)
    }

    @MainActor
    func test_return_assignment_rejected_no_binding() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let empty = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "X",
            attachedDevice: "   ",
            attachedFleetVehicleToken: nil
        )
        XCTAssertEqual(run.returnAssignmentToReservePool(empty, forTaskID: tid), .rejectedNoBinding)
    }

    @MainActor
    func test_return_assignment_rejected_written_off() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let simUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let key = "sitl:\(simUUID.uuidString)"
        run.markFleetVehicleWrittenOffForReservePool(storageKey: key)
        let assignment = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "P1",
            attachedDevice: "",
            attachedFleetVehicleToken: key
        )
        XCTAssertEqual(
            run.returnAssignmentToReservePool(assignment, forTaskID: tid),
            .rejectedFleetVehicleWrittenOff(storageKey: key)
        )
    }

    @MainActor
    func test_return_assignment_rejected_fleet_context_unavailable() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let run = MissionRunEnvironment(mission: mission)
        let tid = task.id
        let simUUID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!
        let key = "sitl:\(simUUID.uuidString)"
        let assignment = MissionRunAssignment(
            rosterDeviceId: UUID(),
            slotName: "P1",
            attachedDevice: "",
            attachedFleetVehicleToken: key
        )
        XCTAssertEqual(run.returnAssignmentToReservePool(assignment, forTaskID: tid), .rejectedFleetContextUnavailable)
    }

    @MainActor
    func test_swap_roster_random_reserve_moves_binding_and_returns_prior_legacy() {
        let task = MissionTask(name: "Alpha")
        let rosterDeviceId = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: rosterDeviceId, name: "Primary", vehicleClass: .unknown),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rosterDeviceId,
            slotName: "Primary",
            attachedDevice: "OLD",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "P1",
                    attachedFleetVehicleToken: nil,
                    attachedDevice: "NEWPOOL"
                ),
            ]),
            forTaskID: tid
        )
        let out = run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: tid)
        guard case .success(let usedPool, let ret) = out else {
            XCTFail("expected success, got \(out)")
            return
        }
        XCTAssertEqual(usedPool, poolSlotID)
        XCTAssertNil(ret)
        XCTAssertEqual(run.assignments[0].attachedDevice, "NEWPOOL")
        let pool = run.reservePool(forTaskID: tid)
        XCTAssertEqual(pool.entries.count, 1)
        let filled = pool.entries.filter(\.hasFleetOrLegacyBinding)
        XCTAssertEqual(filled.count, 1)
        XCTAssertEqual(filled[0].attachedDevice, "OLD")
        XCTAssertEqual(filled[0].id, poolSlotID)
    }

    @MainActor
    func test_swap_no_eligible_pool_slots() {
        let task = MissionTask(name: "Alpha")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: task.id),
            .noEligiblePoolSlots
        )
    }

    @MainActor
    func test_swap_assignment_not_bound_to_task() {
        let tA = MissionTask(name: "A")
        let tB = MissionTask(name: "B")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [tA, tB])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: tA.id,
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "P", attachedDevice: "Y"),
            ]),
            forTaskID: tB.id
        )
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: tB.id),
            .assignmentNotBoundToTask
        )
    }

    @MainActor
    func test_swap_identical_fleet_token_only_noop() {
        let sim = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let key = "sitl:\(sim.uuidString)"
        let task = MissionTask(name: "T")
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: UUID(),
            slotName: "Primary",
            attachedDevice: "",
            attachedFleetVehicleToken: key
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "P1", attachedFleetVehicleToken: key, attachedDevice: "Sim1"),
            ]),
            forTaskID: task.id
        )
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: task.id),
            .identicalFleetBindingNoOp
        )
    }

    @MainActor
    func test_swap_typed_vacancy_rejects_legacy_pool_without_fleet_type() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "BOUND",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "P1", attachedFleetVehicleToken: nil, attachedDevice: "LEGACY_POOL"),
            ]),
            forTaskID: task.id
        )
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: task.id),
            .noClassCompatiblePoolSlots
        )
    }

    @MainActor
    func test_available_reserve_pool_entries_respects_assignment_class_gate() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        let tid = task.id
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(label: "leg", attachedFleetVehicleToken: nil, attachedDevice: "CALL"),
            ]),
            forTaskID: tid
        )
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid).count, 1)
        XCTAssertEqual(run.availableReservePoolEntries(forTaskID: tid, classCompatibleWithAssignmentId: assignID).count, 0)
    }

    @MainActor
    func test_swap_live_pool_class_mismatch_returns_no_class_compatible() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavFixedWing)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "LEGACY",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "P1",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: tid),
            .noClassCompatiblePoolSlots
        )
    }

    @MainActor
    func test_swap_live_pool_class_match_succeeds() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", vehicleClass: .uavCopter)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "LEGACY",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "P1",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        let out = run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: tid)
        guard case .success(let used, _) = out else {
            XCTFail("expected success, got \(out)")
            return
        }
        XCTAssertEqual(used, poolSlotID)
        XCTAssertEqual(run.assignments[0].attachedFleetVehicleToken, "live")
    }

    @MainActor
    func test_swap_live_pool_ugv_wheeled_template_accepts_tracked_reserve() {
        let task = MissionTask(name: "Alpha")
        let rd = UUID()
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "G1", vehicleClass: .ugvWheeled)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let roster = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "LEGACY",
            attachedFleetVehicleToken: nil
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .ugvTracked)
        let run = MissionRunEnvironment(mission: mission, assignments: [roster])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "P1",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        let out = run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: assignID, taskID: tid)
        guard case .success(let used, _) = out else {
            XCTFail("expected success, got \(out)")
            return
        }
        XCTAssertEqual(used, poolSlotID)
        XCTAssertEqual(run.assignments[0].attachedFleetVehicleToken, "live")
    }

    @MainActor
    func test_swap_precommit_aborts_when_fleet_token_already_on_other_roster_slot() {
        let primaryID = UUID()
        let wingID = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [primaryID, wingID])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [
                RosterDevice(id: primaryID, name: "Lead", slot: .primary, vehicleClass: .unknown),
                RosterDevice(id: wingID, name: "Wing", slot: .wingman, vehicleClass: .unknown),
            ],
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let vacancyID = UUID()
        let wingAssignID = UUID()
        let vacancy = MissionRunAssignment(
            id: vacancyID,
            taskId: task.id,
            rosterDeviceId: primaryID,
            slotName: "Primary",
            attachedDevice: "LEGACY",
            attachedFleetVehicleToken: nil
        )
        let wing = MissionRunAssignment(
            id: wingAssignID,
            taskId: task.id,
            rosterDeviceId: wingID,
            slotName: "Wing",
            attachedDevice: "W",
            attachedFleetVehicleToken: "live"
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy, wing])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "Pool",
                    attachedFleetVehicleToken: "live",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: vacancyID, taskID: tid),
            .pickRejectedDuplicateOrStaleBinding
        )
    }

    @MainActor
    func test_swap_precommit_aborts_when_same_fleet_token_in_two_pool_berths() {
        let rd = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [rd])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let vacancyID = UUID()
        let vacancy = MissionRunAssignment(
            id: vacancyID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let s1 = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
        let s2 = UUID(uuidString: "00000000-0000-0000-0000-0000000000F3")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: s1, label: "A", attachedFleetVehicleToken: "live", attachedDevice: ""),
                MissionRunReservePoolSlot(id: s2, label: "B", attachedFleetVehicleToken: "live", attachedDevice: ""),
            ]),
            forTaskID: tid
        )
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: vacancyID, taskID: tid),
            .pickRejectedDuplicateOrStaleBinding
        )
    }

    @MainActor
    func test_swap_returns_noEligiblePoolSlots_when_fleet_token_written_off_before_swap() {
        let rd = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [rd])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let fleet = FleetLinkService()
        let sitl = SitlService()
        sitl.attachFleetLink(fleet)
        fleet.seedMissionRunTestLiveVehicle(vehicleID: "sysid:9", vehicleType: .uavCopter)
        let vacancyID = UUID()
        let vacancy = MissionRunAssignment(
            id: vacancyID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedDevice: "X",
            attachedFleetVehicleToken: nil
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        run.attachServices(fleetLink: fleet, sitl: sitl)
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F4")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(id: poolSlotID, label: "P1", attachedFleetVehicleToken: "live", attachedDevice: ""),
            ]),
            forTaskID: tid
        )
        run.markFleetVehicleWrittenOffForReservePool(storageKey: "live")
        XCTAssertEqual(
            run.swapRosterAssignmentWithRandomFloatingReserve(assignmentID: vacancyID, taskID: tid),
            .noEligiblePoolSlots
        )
    }

    @MainActor
    func test_enumerate_reserve_swap_candidates_includes_pool_when_vacancy_slot_shows_blocked_no_vehicle() {
        let rd = UUID()
        let task = MissionTask(name: "Alpha", rosterDeviceIds: [rd])
        let mission = Mission(
            id: UUID(),
            name: "M",
            description: "",
            type: .mobile,
            rosterDevices: [RosterDevice(id: rd, name: "P1", slot: .primary, vehicleClass: .unknown)],
            routeMacro: RouteMacro(tasks: [task])
        )
        let assignID = UUID()
        let blockedLanes = MissionRunAssignmentSlotStateLanes(commanded: .idle, observed: .blockedNoVehicle)
        let vacancy = MissionRunAssignment(
            id: assignID,
            taskId: task.id,
            rosterDeviceId: rd,
            slotName: "Primary",
            attachedFleetVehicleToken: "vacancy-token",
            slotLifecycleLanes: blockedLanes
        )
        let run = MissionRunEnvironment(mission: mission, assignments: [vacancy])
        let tid = task.id
        let poolSlotID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        run.setReservePool(
            MissionRunReservePool(entries: [
                MissionRunReservePoolSlot(
                    id: poolSlotID,
                    label: "R1",
                    attachedFleetVehicleToken: "pool-token",
                    attachedDevice: ""
                ),
            ]),
            forTaskID: tid
        )
        let cands = run.enumerateReserveSwapCandidates(vacancyAssignmentID: assignID, taskID: tid)
        XCTAssertTrue(
            cands.contains { cand in
                if case .floatingPool(_, let slot) = cand { return slot.id == poolSlotID }
                return false
            },
            "pool candidate must remain visible despite vacancy roster slot evidence"
        )
    }
}

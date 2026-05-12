import Foundation

// MARK: - Floating reserve pool (run-only)

/// One **floating reserve slot** on a task (MCS-only; not persisted on ``Mission`` templates).
/// A slot is an **empty or filled berth**: `attachedFleetVehicleToken` / `attachedDevice` bind which vehicle currently occupies it.
/// **Vehicle lifecycle** (written off, battery gates, etc.) belongs on ``MissionRunEnvironment`` / fleet models — not on this row.
/// Architecture: **README.md** → **Floating reserve pool (Mission Control run)**; deferred work: **NEXTVERSION.md** → **Floating reserve pool — deferred phases** (2026-05-12).
struct MissionRunReservePoolSlot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Operator-facing label for the slot row (not the fleet storage key).
    var label: String
    /// Fleet vehicle bound into this slot, if any (`FleetMissionVehicleToken.storageKey` form).
    var attachedFleetVehicleToken: String?
    /// Legacy free-text device binding when no fleet token exists.
    var attachedDevice: String

    init(
        id: UUID = UUID(),
        label: String,
        attachedFleetVehicleToken: String? = nil,
        attachedDevice: String = ""
    ) {
        self.id = id
        self.label = label
        self.attachedFleetVehicleToken = attachedFleetVehicleToken
        self.attachedDevice = attachedDevice
    }

    /// Same readiness rule as ``MissionRunAssignment/hasFleetOrLegacyAssignment`` — slot is **filled**.
    var hasFleetOrLegacyBinding: Bool {
        if let t = attachedFleetVehicleToken, !t.isEmpty { return true }
        return !attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Second line for MC-R **read-only** floating reserve chips: fleet short id when resolved, else legacy device, else **Bound** / **Empty**.
    func floatingReserveMcReadOnlyBindingDisplay(resolvedFleetDisplayShortID: String?) -> String {
        guard hasFleetOrLegacyBinding else { return "Empty" }
        if let s = resolvedFleetDisplayShortID?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        let d = attachedDevice.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? "Bound" : d
    }
}

/// Backwards-compatible type name used across Mission Control until call sites adopt ``MissionRunReservePoolSlot``.
typealias MissionRunReservePoolEntry = MissionRunReservePoolSlot

/// Per-task collection of floating reserve **slots** (run envelope).
struct MissionRunReservePool: Codable, Equatable, Sendable {
    var entries: [MissionRunReservePoolSlot]

    init(entries: [MissionRunReservePoolSlot] = []) {
        self.entries = entries
    }

    /// Appends ``payload`` or replaces the first row whose fleet token equals ``mergeFleetStorageKey`` (trimmed, non-empty).
    mutating func applyReservePoolReturnPayload(
        _ payload: MissionRunReservePoolSlot,
        mergeFleetStorageKey: String?
    ) -> MissionRunReservePoolReturnAssignmentOutcome {
        if let key = mergeFleetStorageKey, !key.isEmpty,
           let idx = entries.firstIndex(where: {
               ($0.attachedFleetVehicleToken ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == key
           }) {
            let slotID = entries[idx].id
            entries[idx] = MissionRunReservePoolSlot(
                id: slotID,
                label: payload.label,
                attachedFleetVehicleToken: payload.attachedFleetVehicleToken,
                attachedDevice: payload.attachedDevice
            )
            return .mergedExisting(slotID: slotID)
        }
        entries.append(payload)
        return .appended(slotID: payload.id)
    }
}

/// Result of ``MissionRunEnvironment/returnAssignmentToReservePool(_:forTaskID:)``.
///
/// **Happy paths:** `appended`, `mergedExisting` — a new or updated pool **slot** binding mirrors the assignment’s device/token.
///
/// **Rejections:** map to operator / MRE handling — **recovery / ground** when the airframe is not ``VehicleLifecycleStage/live``;
/// **re-charge / swap battery** when ``FleetVehicleBatteryTrafficBand/critical``; **fleet / hub** when services cannot resolve the token.
enum MissionRunReservePoolReturnAssignmentOutcome: Equatable, Sendable {
    case appended(slotID: UUID)
    case mergedExisting(slotID: UUID)

    case rejectedNoBinding
    case rejectedFleetVehicleWrittenOff(storageKey: String)
    case rejectedFleetContextUnavailable
    case rejectedFleetVehicleUnresolved
    case rejectedVehicleNotOperational(stage: VehicleLifecycleStage)
    case rejectedBatteryCritical
}

/// Result of ``MissionRunEnvironment/swapRosterAssignmentWithRandomFloatingReserve(assignmentID:taskID:triggerSource:)``.
enum MissionRunFloatingReserveSwapOutcome: Equatable, Sendable {
    /// Prior roster binding was returned to the pool only when it had a binding; `nil` when the slot was empty.
    case success(usedPoolSlotID: UUID, returnedPriorBindingToPool: MissionRunReservePoolReturnAssignmentOutcome?)
    case noEligiblePoolSlots
    case assignmentNotFound
    case assignmentNotBoundToTask
    /// Picked pool row would not change the roster binding (same fleet storage key).
    case identicalFleetBindingNoOp
    /// Prior airframe could not re-enter the pool (battery / lifecycle / written-off / hub); swap aborted with no mutations.
    case returnRejected(MissionRunReservePoolReturnAssignmentOutcome)
    /// Clearing the drawn pool berth failed after a successful return-to-pool (extremely rare); state may be inconsistent — operator should refresh the run.
    case poolClearFailed
}

extension FleetVehicleOperationalModel {
    /// When non-`nil`, the vehicle must not re-enter the floating reserve pool from a squad assignment until the condition clears.
    func reservePoolReturnFromAssignmentRejection() -> MissionRunReservePoolReturnAssignmentOutcome? {
        if let st = lifecycleStatus?.stage, st != .live {
            return .rejectedVehicleNotOperational(stage: st)
        }
        if battery.trafficBand == .critical {
            return .rejectedBatteryCritical
        }
        return nil
    }

    /// Same lifecycle + battery bar as MRE **draw** eligibility and ``MissionRunEnvironment/returnAssignmentToReservePool``.
    var qualifiesForMissionRunReservePoolOperationalDraw: Bool {
        reservePoolReturnFromAssignmentRejection() == nil
    }
}

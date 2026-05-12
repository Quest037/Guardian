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
            let preservedLabel = entries[idx].label
            entries[idx] = MissionRunReservePoolSlot(
                id: slotID,
                label: preservedLabel,
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
/// **Happy paths:** `appended`, `mergedExisting` — pool **binding** (token / legacy device) comes from the assignment; **labels** stay pool-berth identity (append uses a new ``Reserve N`` style label; merge keeps the matched row’s existing label).
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

/// Result of ``MissionRunEnvironment/swapRosterAssignmentWithRandomFloatingReserve(assignmentID:taskID:triggerSource:rankingPolicy:)``.
enum MissionRunFloatingReserveSwapOutcome: Equatable, Sendable {
    /// Prior roster binding moved onto the **same** pool berth that supplied the reserve (no new pool rows). `returnedPriorBindingToPool` is `nil` for this in-place swap; non-`nil` only if a future path appends again.
    case success(usedPoolSlotID: UUID, returnedPriorBindingToPool: MissionRunReservePoolReturnAssignmentOutcome?)
    case noEligiblePoolSlots
    /// Pool has filled berths, but none match this roster slot’s template ``RosterDevice/vehicleClass`` under ``FleetVehicleSubstitutionPolicy/missionRunReserveSwap``.
    case noClassCompatiblePoolSlots
    case assignmentNotFound
    case assignmentNotBoundToTask
    /// Picked pool row would not change the roster binding (same fleet storage key).
    case identicalFleetBindingNoOp
    /// Prior airframe could not re-enter the pool (battery / lifecycle / written-off / hub); swap aborted with no mutations.
    case returnRejected(MissionRunReservePoolReturnAssignmentOutcome)
    /// Picked pool row failed a **last-moment** dedupe or operational re-check (e.g. fleet token appeared on another roster slot, duplicated across pool berths, written off, or battery/lifecycle no longer qualifies) — no roster or pool mutations.
    case pickRejectedDuplicateOrStaleBinding
    /// Operator-selected pool berth is not in ``MissionRunEnvironment/enumerateReserveSwapCandidates`` for this vacancy (wrong task, class gate, duplicate token, etc.).
    case poolSlotNotEligible
    /// Clearing the drawn pool berth failed after a successful return-to-pool (extremely rare); state may be inconsistent — operator should refresh the run.
    case poolClearFailed
}

/// Result of ``MissionRunEnvironment/swapRosterVacancyWithFixedTemplateReserveAssignment(vacancyAssignmentID:reserveAssignmentID:taskID:triggerSource:)``.
///
/// Swaps ``attachedFleetVehicleToken`` / ``attachedDevice`` between a **primary or wingman** vacancy and a **template `.reserve`**
/// roster row on the same task — no floating pool rows. Pre-commit rules mirror ``enumerateReserveSwapCandidates`` eligibility plus
/// last-moment dedupe / operational re-checks aligned with floating pool swap-in.
enum MissionRunFixedRosterReserveSwapOutcome: Equatable, Sendable {
    case success
    case assignmentNotFound
    case assignmentNotBoundToTask
    /// ``reserveAssignmentID`` is not a **fixed roster reserve** candidate for this vacancy (wrong task, class drift, duplicate token, written off, operational gate, etc.).
    case reserveNotEligibleForVacancy
    /// Same normalized fleet token on both rows — no mutation.
    case identicalFleetBindingNoOp
    /// Last-moment dedupe / operational / written-off re-check failed — no mutations.
    case pickRejectedDuplicateOrStaleBinding
}

/// One **replace-aircraft** option for a roster vacancy: floating pool berth or template **reserve** row on the same task.
///
/// Built by ``MissionRunEnvironment/enumerateReserveSwapCandidates(vacancyAssignmentID:taskID:ordering:)``. ``MissionRunEnvironment/swapRosterAssignmentWithRandomFloatingReserve``
/// draws only **pool** rows; fixed roster reserves use ``MissionRunEnvironment/swapRosterVacancyWithFixedTemplateReserveAssignment``.
///
/// **Naming:** ``ReserveSwapCandidate`` is a typealias to this enum — one union type for pool + fixed roster reserve (pool berth id via ``MissionRunReservePoolSlot/id``; fixed row via ``MissionRunAssignment`` snapshot on a template **reserve** roster device).
enum MissionRunReserveSwapCandidate: Equatable, Identifiable {
    case floatingPool(taskID: UUID, slot: MissionRunReservePoolSlot)
    case fixedRosterReserve(assignment: MissionRunAssignment)

    var id: String {
        switch self {
        case .floatingPool(let taskID, let slot):
            return "pool.\(taskID.uuidString).\(slot.id.uuidString)"
        case .fixedRosterReserve(let a):
            return "roster.\(a.id.uuidString)"
        }
    }
}

/// How ``MissionRunEnvironment/enumerateReserveSwapCandidates`` orders **floating pool** vs **fixed template reserve** rows in the returned array.
///
/// **Operator surfaces** (MC-R pool picker, MCS triage) keep ``poolSlotsFirst`` so pool berths stay ahead of bench roster rows. **Autonomous / headless**
/// callers that walk candidates in array order should use ``fixedRosterReservesFirst`` so template `.reserve` bindings are considered before pool berths.
enum MissionRunReserveSwapCandidateOrdering: Equatable, Sendable {
    case poolSlotsFirst
    case fixedRosterReservesFirst
}

/// Alias for ``MissionRunReserveSwapCandidate`` — **reserve swap candidate union** (floating pool vs fixed roster reserve).
///
/// Use this name in new call sites and docs when referring to the unified model; the underlying type is identical for ``Equatable``, ``Identifiable``, and ranking APIs.
typealias ReserveSwapCandidate = MissionRunReserveSwapCandidate

/// How to choose among ``ReserveSwapCandidate`` / ``MissionRunReserveSwapCandidate`` rows for swap-in / reserve-replace flows.
///
/// v1 implements **uniform random** only (current MCS / MRE floating-pool draw). Extend with new cases and ``pick(from:)``
/// when operator-chosen rows, battery-soonest, map proximity, or Paladin-ranked picks ship.
enum MissionRunReserveSwapRankingPolicy: String, Equatable, Codable, CaseIterable, Sendable {
    case uniformRandom

    /// Picks one candidate; returns `nil` when the list is empty.
    func pick(from candidates: [ReserveSwapCandidate]) -> ReserveSwapCandidate? {
        guard !candidates.isEmpty else { return nil }
        switch self {
        case .uniformRandom:
            return candidates.randomElement()
        }
    }
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

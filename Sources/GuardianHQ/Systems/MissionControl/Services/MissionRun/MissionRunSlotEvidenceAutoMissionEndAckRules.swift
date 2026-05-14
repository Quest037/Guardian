import Foundation

/// One roster row that still blocks §3 **automatic** mission-end ack until its merged lane reaches ``policySucceeded``.
struct MissionRunAutoMissionEndAckSlotRowSnapshot: Equatable, Sendable {
    let assignmentID: UUID
    let slotName: String
    let mergedState: MissionRunAssignmentSlotState
}

/// §3 rollup: when all bound roster rows show merged slot ``policySucceeded``, a task may receive automatic
/// mission-end ack (see ``MissionRunEnvironment/applySlotEvidenceAutoMissionEndAckIfNeeded(forAssignmentIDs:)``).
enum MissionRunSlotEvidenceAutoMissionEndAckRules {
    /// True when merged policy state is a **settled** outcome for **complete** mission-end auto-ack: success, a
    /// terminal failure after policy-shaped traffic (e.g. one vehicle took an abort tactic under the same operator
    /// “complete” envelope), or a non-participating slot. Still excludes in-flight and ``blockedNoVehicle``.
    static func mergedSlotSettledForCompleteMissionEndAutoAck(_ row: MissionRunAssignment) -> Bool {
        let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: row.effectiveSlotLifecycleLanes)
        switch merged {
        case .policySucceeded, .policyFailed, .notApplicableEmptySlot:
            return true
        case .idle, .staging, .executingMission, .betweenCycles, .policyAborting, .policyCompleting,
             .blockedNoVehicle, .supersededReassigned:
            return false
        }
    }

    /// One row per task: every bound roster row must be ``mergedSlotSettledForCompleteMissionEndAutoAck`` before
    /// ``MissionRunEnvironment`` inserts ``taskMissionEndRecoveryCompletedByTaskID`` for an issued complete wind-down.
    static func allBoundRosterRowsSatisfiedForCompleteMissionEndAutoAck(_ rows: [MissionRunAssignment]) -> Bool {
        guard !rows.isEmpty else { return false }
        return rows.allSatisfy { mergedSlotSettledForCompleteMissionEndAutoAck($0) }
    }

    /// Rows still blocking **complete**-intent automatic mission-end ack (for MC-R triage chrome).
    static func boundRosterRowsBlockingCompleteMissionEndAutoAck(_ rows: [MissionRunAssignment]) -> [MissionRunAutoMissionEndAckSlotRowSnapshot] {
        let snaps: [MissionRunAutoMissionEndAckSlotRowSnapshot] = rows.compactMap { row in
            guard !mergedSlotSettledForCompleteMissionEndAutoAck(row) else { return nil }
            let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: row.effectiveSlotLifecycleLanes)
            let trimmed = row.slotName.trimmingCharacters(in: .whitespacesAndNewlines)
            let slotName = trimmed.isEmpty ? "Roster slot" : trimmed
            return MissionRunAutoMissionEndAckSlotRowSnapshot(
                assignmentID: row.id,
                slotName: slotName,
                mergedState: merged
            )
        }
        return snaps.sorted {
            let c = $0.slotName.localizedCaseInsensitiveCompare($1.slotName)
            if c != .orderedSame { return c == .orderedAscending }
            return $0.assignmentID.uuidString < $1.assignmentID.uuidString
        }
    }

    /// True when there is at least one bound row and **every** row’s ``MissionRunAssignmentSlotLaneMerge/preferredDisplayState``
    /// is ``policySucceeded``.
    ///
    /// **Partial fleet (v1 lock):** if **any** bound row is not ``policySucceeded`` (including ``blockedNoVehicle`` or
    /// ``policyFailed`` on another slot while others already succeeded), auto mission-end ack **does not** run — the
    /// operator fixes binding / fleet failures or uses manual triage. **Empty / N/A rows:** every row in the bound set
    /// must reach merged ``policySucceeded``; see README **Mission run state model** → **Modeling locks (v1 shipped)** §4.
    static func allBoundRosterRowsPolicySucceeded(_ rows: [MissionRunAssignment]) -> Bool {
        guard !rows.isEmpty else { return false }
        return rows.allSatisfy { row in
            MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: row.effectiveSlotLifecycleLanes)
                == .policySucceeded
        }
    }

    /// When true, at least one bound roster row shows merged **binding or policy failure** on the chip merge path, so
    /// slot-evidence auto mission-end ack must **not** fire until that row clears (v1 **partial fleet** stance).
    static func partialFleetBindingOrPolicyFailureBlocksAutoMissionEndAck(_ rows: [MissionRunAssignment]) -> Bool {
        rows.contains { row in
            switch MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: row.effectiveSlotLifecycleLanes) {
            case .blockedNoVehicle, .policyFailed:
                return true
            default:
                return false
            }
        }
    }

    /// Bound roster rows whose merged display state is **not** ``policySucceeded`` — these prevent automatic
    /// mission-end ack until every row settles (``TaskRosterAssignmentStatesToDo.md`` §3 partial roster lock).
    /// Sorted by ``slotName`` then ``assignmentID`` for stable operator lists.
    static func boundRosterRowsBlockingAutoMissionEndAck(_ rows: [MissionRunAssignment]) -> [MissionRunAutoMissionEndAckSlotRowSnapshot] {
        let snaps: [MissionRunAutoMissionEndAckSlotRowSnapshot] = rows.compactMap { row in
            let merged = MissionRunAssignmentSlotLaneMerge.preferredDisplayState(lanes: row.effectiveSlotLifecycleLanes)
            guard merged != .policySucceeded else { return nil }
            let trimmed = row.slotName.trimmingCharacters(in: .whitespacesAndNewlines)
            let slotName = trimmed.isEmpty ? "Roster slot" : trimmed
            return MissionRunAutoMissionEndAckSlotRowSnapshot(
                assignmentID: row.id,
                slotName: slotName,
                mergedState: merged
            )
        }
        return snaps.sorted {
            let c = $0.slotName.localizedCaseInsensitiveCompare($1.slotName)
            if c != .orderedSame { return c == .orderedAscending }
            return $0.assignmentID.uuidString < $1.assignmentID.uuidString
        }
    }
}

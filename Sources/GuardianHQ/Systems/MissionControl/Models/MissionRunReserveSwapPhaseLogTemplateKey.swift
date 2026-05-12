import Foundation

// MARK: - Reserve swap phase log templates

/// Stable ``MissionRunEvent/templateKey`` ids for **live reserve swap-in** pipeline phases
/// (``MissionRosterReservesToDo.md``). Shape: `missioncontrol.mre.reserve.phase.<slug>.(pass|fail)`.
///
/// Emit with ``templateParams(phase:correlation:detail:recipeRaw:)`` so export / MCR / Paladin
/// share the same parameter vocabulary.
enum MissionRunReserveSwapPhaseLogTemplateKey: Sendable {

    /// URL/log-safe slug for ``templateParams`` key `phase` (matches the dotted key segment).
    static func phaseSlug(for phase: MissionRunReserveSwapPipelinePhase) -> String {
        switch phase {
        case .pickReserve: return "pick_reserve"
        case .swapTimeChecks: return "swap_time_checks"
        case .missionUpload: return "mission_upload"
        case .reposition: return "reposition"
        case .rosterCommit: return "roster_commit"
        }
    }

    static func templateKey(phase: MissionRunReserveSwapPipelinePhase, passed: Bool) -> String {
        let slug = phaseSlug(for: phase)
        return passed
            ? "missioncontrol.mre.reserve.phase.\(slug).pass"
            : "missioncontrol.mre.reserve.phase.\(slug).fail"
    }

    /// Every pass/fail key registered in ``StructuredLogTemplateCatalog`` (for catalogue parity tests).
    static func allTemplateKeys() -> [String] {
        MissionRunReserveSwapPipelinePhase.allCases.flatMap { p in
            [templateKey(phase: p, passed: true), templateKey(phase: p, passed: false)]
        }
    }

    /// Standard ``appendLogEvent(templateParams:)`` map: ids, `phase` slug, `vehicleID`, `detail`,
    /// optional `recipe` (raw recipe name) for swap-time recipe gates.
    static func templateParams(
        phase: MissionRunReserveSwapPipelinePhase,
        correlation: MissionRunReserveRecipeRunnerCorrelation,
        detail: String,
        recipeRaw: String? = nil
    ) -> [String: String] {
        var m: [String: String] = [
            "phase": phaseSlug(for: phase),
            "missionRunID": correlation.missionRunID.uuidString,
            "missionTaskID": correlation.missionTaskID.uuidString,
            "vacancyAssignmentID": correlation.vacancyAssignmentID.uuidString,
            "reserveStreamAssignmentID": correlation.reserveStreamAssignmentID.uuidString,
            "poolSlotID": correlation.reservePoolSlotID?.uuidString ?? "-",
            "vehicleID": correlation.vehicleID,
            "detail": detail,
        ]
        if let r = recipeRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            m["recipe"] = r
        }
        return m
    }
}

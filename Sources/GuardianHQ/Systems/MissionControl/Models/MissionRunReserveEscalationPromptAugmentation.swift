import Foundation

// MARK: - Recipe escalation → reserve swap hint (MC-R)

/// When a fleet recipe escalates with ``FleetRecipeUnrecoverableFailureKind/needsAirframeReplacement`` inside a
/// ``MissionRunEnvironment``, augments the operator prompt with **class-matched reserve** availability (same rules
/// as ``MissionRunEnvironment/enumerateReserveSwapCandidates``).
enum MissionRunReserveEscalationPromptAugmentation {

    struct Result: Equatable, Sendable {
        let extraFacts: [OperatorPromptContextFact]
        let bodyAppendix: String?
    }

    @MainActor
    static func augmentation(
        run: MissionRunEnvironment,
        vacancyAssignmentID: UUID,
        missionTaskID: UUID?,
        escalation: FleetRecipeEscalationEvent
    ) -> Result {
        guard case .unrecoverableFailure(let kind) = escalation.reason,
              kind == .needsAirframeReplacement
        else {
            return Result(extraFacts: [], bodyAppendix: nil)
        }
        let taskID = missionTaskID
            ?? run.assignments.first(where: { $0.id == vacancyAssignmentID })?.taskId
        guard let taskID else {
            return Result(
                extraFacts: [
                    OperatorPromptContextFact(
                        label: "Reserve swap",
                        value: "This slot is not bound to a task — use Mission Control roster triage to swap manually if needed.",
                        emphasis: .normal,
                        group: "Mission"
                    ),
                ],
                bodyAppendix: nil
            )
        }
        let candidates = run.enumerateReserveSwapCandidates(
            vacancyAssignmentID: vacancyAssignmentID,
            taskID: taskID
        )
        let count = candidates.count
        let facts: [OperatorPromptContextFact] = [
            OperatorPromptContextFact(
                label: "Class-matched reserves",
                value: count == 0 ? "None on this task." : "\(count) on this task (pool + fixed reserve rows).",
                emphasis: count == 0 ? .warning : .normal,
                group: "Mission"
            ),
        ]
        let appendix: String?
        if count > 0 {
            appendix =
                "When a reserve is ready, use **Swap in reserve** on this slot (Mission Control task triage or live roster strip) after hub checks pass."
        } else {
            appendix =
                "Add or bind a class-compatible floating reserve on this task, or fix the aircraft, before continuing this recipe."
        }
        return Result(extraFacts: facts, bodyAppendix: appendix)
    }
}

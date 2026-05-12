import Foundation

/// Presents MRE-driven recipe escalations on the Mission Control Run (MC-R) surface using
/// ``OperatorPromptEvent`` + ``OperatorPromptResumptionChannel`` — **not** the Vehicle Inspector
/// wizard mirror on ``FleetRecipeRunner`` (that UI assumes an open inspector).
@MainActor
final class MissionRunRecipeOperatorPromptBridge: ObservableObject {

    static let shared = MissionRunRecipeOperatorPromptBridge()

    /// Active operator prompts for a run (multiple slots can escalate in parallel).
    @Published private(set) var activePromptsByMissionRunID: [UUID: [OperatorPromptEvent]] = [:]

    private init() {}

    /// Suspend until the operator answers (or timeout / cancellation resolves via the channel).
    func awaitMissionRecipeEscalationAnswer(
        missionRunID: UUID,
        assignmentID: UUID,
        missionTaskID: UUID?,
        slotLabel: String,
        escalation: FleetRecipeEscalationEvent
    ) async -> FleetRecipeResumptionVerb {
        let target = OperatorPromptTarget(
            missionRunID: missionRunID,
            missionTaskID: missionTaskID,
            affectedAssignmentID: assignmentID,
            affectedVehicleID: escalation.vehicleID,
            recipeRunID: escalation.runID
        )
        let extraFacts: [OperatorPromptContextFact] = [
            OperatorPromptContextFact(label: "Roster slot", value: slotLabel, group: "Where"),
        ]
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            target: target,
            contextFacts: extraFacts
        )
        register(event, missionRunID: missionRunID)
        defer { unregister(promptID: event.id, missionRunID: missionRunID) }
        let answer = await OperatorPromptResumptionChannel.shared.awaitAnswer(for: event)
        return answer.verb
    }

    func submitOperatorAnswer(_ answer: OperatorPromptAnswer) {
        _ = OperatorPromptResumptionChannel.shared.submit(answer)
    }

    func resolveExpiry(for event: OperatorPromptEvent) {
        _ = OperatorPromptResumptionChannel.shared.resolveExpiry(for: event)
    }

    func activePrompts(forMissionRunID runID: UUID) -> [OperatorPromptEvent] {
        activePromptsByMissionRunID[runID] ?? []
    }

    private func register(_ event: OperatorPromptEvent, missionRunID: UUID) {
        var copy = activePromptsByMissionRunID
        var list = copy[missionRunID] ?? []
        list.append(event)
        copy[missionRunID] = list
        activePromptsByMissionRunID = copy
    }

    private func unregister(promptID: UUID, missionRunID: UUID) {
        var copy = activePromptsByMissionRunID
        guard var list = copy[missionRunID] else { return }
        list.removeAll { $0.id == promptID }
        if list.isEmpty {
            copy.removeValue(forKey: missionRunID)
        } else {
            copy[missionRunID] = list
        }
        activePromptsByMissionRunID = copy
    }
}

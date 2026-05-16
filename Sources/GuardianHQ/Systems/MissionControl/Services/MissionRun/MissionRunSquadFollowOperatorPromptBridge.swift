import Foundation

/// MC-R operator prompts when squad wingman OFFBOARD / Guided follow cannot be restored.
@MainActor
enum MissionRunSquadFollowOperatorPromptBridge {

  private static var inFlightPromptPrimaryIDs: Set<UUID> = []

  /// Presents a non-blocking prompt; invokes ``onResolved`` on the main actor when the operator answers.
  static func presentFormationFollowFailure(
    missionRunID: UUID,
    primaryAssignmentID: UUID,
    primarySlotName: String,
    taskID: UUID,
    taskName: String,
    failedWingmen: [(assignmentID: UUID, slotName: String)],
    onResolved: @escaping @MainActor (FleetRecipeResumptionVerb) -> Void
  ) {
    guard inFlightPromptPrimaryIDs.insert(primaryAssignmentID).inserted else { return }
    let wingmanSummary = failedWingmen.map(\.slotName).joined(separator: ", ")
    let target = OperatorPromptTarget(
      missionRunID: missionRunID,
      missionTaskID: taskID,
      affectedAssignmentID: primaryAssignmentID,
      affectedVehicleID: nil
    )
    let facts: [OperatorPromptContextFact] = [
      OperatorPromptContextFact(label: "Task", value: taskName, group: "Where"),
      OperatorPromptContextFact(label: "Primary", value: primarySlotName, group: "Where"),
      OperatorPromptContextFact(
        label: "Wingmen affected",
        value: wingmanSummary.isEmpty ? "—" : wingmanSummary,
        group: "Where"
      ),
    ]
    let options: [OperatorPromptOption] = [
      OperatorPromptOption(
        id: "retry_formation",
        humanLabel: "Retry formation",
        summary: "Resume wingman follow streams and continue the primary mission when ready.",
        role: .confirm,
        verb: .acknowledge
      ),
      OperatorPromptOption(
        id: "park_squad",
        humanLabel: "Park squad",
        summary: "Hold the primary and park the squad until you choose Continue mission.",
        role: .neutral,
        verb: .abort
      ),
    ]
    let event = OperatorPromptEvent(
      origin: .freeform(source: "missioncontrol.mre.squad_follow.stream_exhausted"),
      displaySource: .mre,
      target: target,
      severity: .error,
      title: "Wingman formation follow lost",
      body: """
        A wingman could not stay in OFFBOARD / Guided follow after several reconnect attempts. \
        The primary mission has been paused so the squad does not continue out of formation.
        """,
      contextFacts: facts,
      options: options,
      allowedVerbs: [.acknowledge, .abort],
      policyKey: "missioncontrol.squad_follow.stream_exhausted.\(primaryAssignmentID.uuidString)"
    )
    Task { @MainActor in
      defer { inFlightPromptPrimaryIDs.remove(primaryAssignmentID) }
      let answer = await OperatorPromptCenter.shared.awaitAnswer(for: event)
      onResolved(answer.verb)
    }
  }
}

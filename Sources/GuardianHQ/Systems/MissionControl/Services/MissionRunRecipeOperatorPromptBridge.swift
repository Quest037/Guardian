import Foundation

/// Presents MRE-driven recipe escalations on the Mission Control Run (MC-R) surface using
/// ``OperatorPromptEvent`` + ``OperatorPromptCenter`` — **not** the Vehicle Inspector
/// wizard mirror on ``FleetRecipeRunner`` (that UI assumes an open inspector).
@MainActor
final class MissionRunRecipeOperatorPromptBridge {

    static let shared = MissionRunRecipeOperatorPromptBridge()

    private init() {}

    /// Suspend until the operator answers (or timeout / cancellation resolves via the center).
    ///
    /// - Parameter recipeIssuerKey: ``MissionRunIssuedCommand/issuerKey`` for the in-flight recipe dispatch. When this is
    ///   ``MissionRunCommandIssuerKey/completePolicyWindDown``, ``confirmInLiveMission`` confirmations auto-acknowledge so
    ///   parallel per-vehicle recovery recipes do not each require a separate operator tap.
    func awaitMissionRecipeEscalationAnswer(
        missionRunID: UUID,
        assignmentID: UUID,
        missionTaskID: UUID?,
        slotLabel: String,
        run: MissionRunEnvironment?,
        recipeIssuerKey: String,
        escalation: FleetRecipeEscalationEvent
    ) async -> FleetRecipeResumptionVerb {
        if recipeIssuerKey == MissionRunCommandIssuerKey.completePolicyWindDown,
           escalation.recipe == FleetMovePointParkRecipeRegistrations.movePointParkRecipeName,
           case .confirmation(let kind) = escalation.reason,
           kind == .confirmInLiveMission {
            return .acknowledge
        }
        let target = OperatorPromptTarget(
            missionRunID: missionRunID,
            missionTaskID: missionTaskID,
            affectedAssignmentID: assignmentID,
            affectedVehicleID: escalation.vehicleID,
            recipeRunID: escalation.runID
        )
        let slotFacts: [OperatorPromptContextFact] = [
            OperatorPromptContextFact(label: "Roster slot", value: slotLabel, group: "Where"),
        ]
        let derived = OperatorPromptEvent.defaultsFor(reason: escalation.reason)
        let aug = run.map {
            MissionRunReserveEscalationPromptAugmentation.augmentation(
                run: $0,
                vacancyAssignmentID: assignmentID,
                missionTaskID: missionTaskID,
                escalation: escalation
            )
        } ?? MissionRunReserveEscalationPromptAugmentation.Result(extraFacts: [], bodyAppendix: nil)
        let mergedBody: String = {
            guard let appendix = aug.bodyAppendix, !appendix.isEmpty else { return derived.body }
            if derived.body.isEmpty { return appendix }
            return derived.body + "\n\n" + appendix
        }()
        let event = OperatorPromptEvent(
            fromRecipeEscalation: escalation,
            target: target,
            title: nil,
            body: mergedBody,
            severity: nil,
            contextFacts: slotFacts + aug.extraFacts,
            displaySource: .mre
        )
        let answer = await OperatorPromptCenter.shared.awaitAnswer(for: event)
        return answer.verb
    }

    func submitOperatorAnswer(_ answer: OperatorPromptAnswer) {
        _ = OperatorPromptCenter.shared.submitAnswer(answer)
    }

    func resolveExpiry(for event: OperatorPromptEvent) {
        _ = OperatorPromptCenter.shared.resolveExpiry(for: event)
    }

    /// Fixed **template reserve** roster row → active primary/wingman swap: Mission Control registers an **MC-R**
    /// operator engagement prompt when disposition is **ask** / **defer** / **handoff**. Headless callers supply
    /// ``OperatorPromptDisplaySource`` (e.g. ``OperatorPromptDisplaySource/assistant`` from a plugin); Mission Control does not map
    /// ``MissionRunCommandIssuerKey`` strings to plugins — use ``MissionControlStore/raiseOperatorPromptSwapInReserve`` `operatorPromptDisplaySource`.
    /// Uses ``OperatorPromptOrigin/mreEngagementAsk`` with ``MissionRunEngagementAction/swapInReserve`` so routing matches other MRE engagement prompts.
    func awaitFixedReserveSwapEngagementConsent(
        missionRunID: UUID,
        primary: MissionRunAssignment,
        reserve: MissionRunAssignment,
        missionTaskID: UUID,
        taskName: String,
        displaySource: OperatorPromptDisplaySource
    ) async -> FleetRecipeResumptionVerb {
        let target = OperatorPromptTarget(
            missionRunID: missionRunID,
            missionTaskID: missionTaskID,
            affectedRosterSlotID: primary.rosterDeviceId,
            affectedAssignmentID: primary.id,
            affectedVehicleID: nil
        )
        let facts: [OperatorPromptContextFact] = [
            OperatorPromptContextFact(label: "Task", value: taskName, group: "Where"),
            OperatorPromptContextFact(label: "Active slot", value: primary.slotName, group: "Where"),
            OperatorPromptContextFact(label: "Reserve slot", value: reserve.slotName, group: "Where"),
            OperatorPromptContextFact(
                label: "Reserve assignment",
                value: reserve.id.uuidString,
                emphasis: .normal,
                group: "Identifiers"
            ),
        ]
        let body: String = {
            switch displaySource {
            case .assistant:
                return "Moving the reserve aircraft bound to “\(reserve.slotName)” onto the active roster slot “\(primary.slotName)”. Confirm only if this matches your intent for this task."
            case .missionControl, .mre:
                return "Rules of engagement require your consent before moving the reserve aircraft bound to “\(reserve.slotName)” onto the active roster slot “\(primary.slotName)”. Confirm only if this matches your intent for this task."
            }
        }()
        let event = OperatorPromptEvent(
            origin: .mreEngagementAsk(runID: missionRunID, action: .swapInReserve),
            displaySource: displaySource,
            target: target,
            severity: .warning,
            title: "Swap in reserve?",
            body: body,
            contextFacts: facts,
            allowedVerbs: [.acknowledge, .abort]
        )
        let answer = await OperatorPromptCenter.shared.awaitAnswer(for: event)
        return answer.verb
    }
}

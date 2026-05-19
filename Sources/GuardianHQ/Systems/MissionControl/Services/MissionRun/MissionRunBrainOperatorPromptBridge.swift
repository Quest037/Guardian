import Foundation

@MainActor
enum MissionRunBrainOperatorPromptBridge {
    private static var inFlightAssignmentIDs: Set<UUID> = []

    static func presentExecutionFailure(
        missionRunID: UUID,
        plan: MissionRunBrainExecutionSubsystem.SegmentLaunchPlan,
        detail: String
    ) {
        guard inFlightAssignmentIDs.insert(plan.assignmentID).inserted else { return }
        let isPlanner = plan.dispatchKind == .plannerOpenLoop
        let target = OperatorPromptTarget(
            missionRunID: missionRunID,
            missionTaskID: plan.taskID,
            affectedAssignmentID: plan.assignmentID,
            affectedVehicleID: plan.vehicleID
        )
        let facts: [OperatorPromptContextFact] = [
            OperatorPromptContextFact(label: "Task", value: plan.taskLabel, group: "Where"),
            OperatorPromptContextFact(label: "Slot", value: plan.slotName, group: "Where"),
            OperatorPromptContextFact(
                label: "Brain",
                value: GuardianBrainRunUtilities.bindingCaption(plan.binding),
                group: "Policy"
            ),
            OperatorPromptContextFact(label: "Detail", value: detail, group: "Evidence"),
        ]
        let event = OperatorPromptEvent(
            origin: .freeform(source: isPlanner ? "missioncontrol.mre.brain.planner_failed" : "missioncontrol.mre.brain.segment_failed"),
            displaySource: .mre,
            target: target,
            severity: .error,
            title: isPlanner ? "Autonomy brain planner run failed" : "Autonomy brain segment run failed",
            body: isPlanner
                ? """
                Open-loop planner segments from the imported brain could not finish on this vehicle. \
                Mission upload was not started for this primary while the brain path was active.
                """
                : """
                Imported brain segments could not finish on this vehicle. \
                Mission upload was not started for this primary while the brain path was active.
                """,
            contextFacts: facts,
            options: [
                OperatorPromptOption(
                    id: "ack_brain_failure",
                    humanLabel: "Acknowledge",
                    summary: "Dismiss this notice and review the mission log.",
                    role: .confirm,
                    verb: .acknowledge
                ),
            ],
            allowedVerbs: [.acknowledge],
            policyKey: "missioncontrol.brain.segment_failed.\(plan.assignmentID.uuidString)"
        )
        Task { @MainActor in
            defer { inFlightAssignmentIDs.remove(plan.assignmentID) }
            _ = await OperatorPromptCenter.shared.awaitAnswer(for: event)
        }
    }
}

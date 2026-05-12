import Foundation
@MainActor
protocol MissionRunPlanningAssistant: AnyObject {
    func missionRun(
        _ run: MissionRunEnvironment,
        planning mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        applyingTo draftPlan: MissionControlPlan
    ) -> MissionControlPlan
}

@MainActor
protocol MissionRunPlanningMutationAssistant: AnyObject {
    func missionRun(
        _ run: MissionRunEnvironment,
        planning mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        shouldApply mutation: MissionControlPlanMutation
    ) -> MissionControlPlanMutation?

    func missionRun(
        _ run: MissionRunEnvironment,
        planning mission: Mission,
        fleetVehicles: [MissionPickableFleetVehicle],
        didApply result: MissionControlPlanChangeResult
    )
}

@MainActor
protocol MissionRunAbortPlanningAssistant: AnyObject {
    /// Adjust a freshly built abort plan. Callbacks are invoked in **lexicographic registration key order**;
    /// register with a key that sorts **last** (e.g. `plugin.paladin.abortPlan`) to win a last-write refinement pass.
    func missionRun(_ run: MissionRunEnvironment, adjustingAbortPlan plan: MissionRunAbortPlan) -> MissionRunAbortPlan
}

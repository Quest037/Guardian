import Foundation

@MainActor
final class MissionRunSystems {
    let lifecycle: MissionRunLifecycleSubsystem
    let logging: MissionRunLoggingSubsystem
    let commands: MissionRunCommandSubsystem
    let planner: MissionRunPlannerSubsystem
    let projections: MissionRunProjectionsSubsystem
    let executor: MissionRunExecutionSubsystem
    let scheduling: MissionRunSchedulingSubsystem
    let policyAuthority: MissionRunPolicyAuthoritySubsystem
    let squadFollow: MissionRunSquadFollowSubsystem
    let brainExecution: MissionRunBrainExecutionSubsystem

    init(
        lifecycle: MissionRunLifecycleSubsystem,
        logging: MissionRunLoggingSubsystem,
        commands: MissionRunCommandSubsystem,
        planner: MissionRunPlannerSubsystem,
        projections: MissionRunProjectionsSubsystem,
        executor: MissionRunExecutionSubsystem,
        scheduling: MissionRunSchedulingSubsystem,
        policyAuthority: MissionRunPolicyAuthoritySubsystem,
        squadFollow: MissionRunSquadFollowSubsystem,
        brainExecution: MissionRunBrainExecutionSubsystem
    ) {
        self.lifecycle = lifecycle
        self.logging = logging
        self.commands = commands
        self.planner = planner
        self.projections = projections
        self.executor = executor
        self.scheduling = scheduling
        self.policyAuthority = policyAuthority
        self.squadFollow = squadFollow
        self.brainExecution = brainExecution
    }
}

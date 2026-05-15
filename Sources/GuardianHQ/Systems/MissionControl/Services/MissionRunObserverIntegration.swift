import Foundation

struct MissionRunObserverPermissions: OptionSet, Equatable {
    let rawValue: Int

    static let observe = MissionRunObserverPermissions(rawValue: 1 << 0)
    static let act = MissionRunObserverPermissions(rawValue: 1 << 1)
    /// Enqueue, replace, or cancel tagged batches on ``MissionRunExecutionSubsystem``’s command queue.
    static let manageExecutionQueue = MissionRunObserverPermissions(rawValue: 1 << 2)
    /// Participate in operator ↔ autonomy handover (e.g. LiveDrive takeover / return).
    static let handoff = MissionRunObserverPermissions(rawValue: 1 << 3)
}

struct MissionRunStartContext {
    let mission: Mission?
    let fleetLink: FleetLinkService
    let sitl: SitlService
    let missionsProvider: @MainActor () -> [Mission]
}

/// Plugins and assistants observe Mission Control runs through this hook.
///
/// Callbacks receive the live ``MissionRunEnvironment`` (same instance the UI uses). For **squad**
/// automation or prompts, read derived and scheduling state on that object — for example
/// ``MissionRunEnvironment/squadStateByAssignmentID``,
/// ``MissionRunEnvironment/pendingMissionSquadGracefulWindDownKindByAssignmentID``,
/// ``MissionRunEnvironment/activeCycleSquadAssignmentIDs``, and task rollups from
/// ``MissionRunEnvironment/taskStateByTaskID`` — rather than expecting a separate squad snapshot type.
@MainActor
protocol MissionControlRunObserver: AnyObject {
    func missionControlStore(
        _ store: MissionControlStore,
        didCreate run: MissionRunEnvironment,
        permissions: MissionRunObserverPermissions
    )

    func missionControlStore(
        _ store: MissionControlStore,
        didStart run: MissionRunEnvironment,
        context: MissionRunStartContext,
        permissions: MissionRunObserverPermissions
    )

    func missionControlStore(
        _ store: MissionControlStore,
        willDelete run: MissionRunEnvironment,
        permissions: MissionRunObserverPermissions
    )
}

extension MissionControlRunObserver {
    func missionControlStore(
        _ store: MissionControlStore,
        didCreate run: MissionRunEnvironment,
        permissions: MissionRunObserverPermissions
    ) {}

    func missionControlStore(
        _ store: MissionControlStore,
        didStart run: MissionRunEnvironment,
        context: MissionRunStartContext,
        permissions: MissionRunObserverPermissions
    ) {}

    func missionControlStore(
        _ store: MissionControlStore,
        willDelete run: MissionRunEnvironment,
        permissions: MissionRunObserverPermissions
    ) {}
}

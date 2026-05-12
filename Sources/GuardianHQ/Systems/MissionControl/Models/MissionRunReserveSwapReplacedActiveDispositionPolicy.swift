import Foundation

// MARK: - Replaced active (ex–primary / wingman) after reserve swap-in

/// **Binding destination** for swap-in commits: ``MissionRunReserveSwapReplacedActiveReturnPathPolicy``.
///
/// Roster / pool bookkeeping for the **prior** active binding displaced by a floating-pool swap.
///
/// Successful ``MissionRunEnvironment/swapRosterAssignmentWithRandomFloatingReserve`` already attempts
/// ``MissionRunEnvironment/returnAssignmentToReservePool`` before the vacancy token is overwritten when the prior row
/// had a binding (see ``MissionRunReserveRosterCommitAtomicityPolicy``).
enum MissionRunReserveSwapReplacedActivePoolDispositionPolicy: Sendable {

    /// A **successful** swap implies the return-to-pool pre-step succeeded whenever the displaced slot had a fleet
    /// binding; otherwise the whole swap fails with ``MissionRunFloatingReserveSwapOutcome/returnRejected``.
    static let successfulSwapRequiresReturnToPoolWhenPriorSlotHadBinding = true

    /// When the **vehicle** cannot participate in pool draws (battery, written-off, unresolved link, etc.), the pool
    /// return path rejects — operators use existing run controls (written-off set via
    /// ``MissionRunEnvironment/markFleetVehicleWrittenOffForReservePool``, alternate disposition) rather than silently
    /// leaving an illegal pool row.
    static let poolReturnRejectionsSurfaceToOperatorWithoutPartialRosterCommit = true
}

// MARK: - Fleet wind-down (RTL / rally / loiter / land / park)

/// **Fleet commands** for the replaced **vehicle** must reuse the same **catalogue / recipe / issued-command** surfaces
/// as Mission Control’s normal recovery and abort planning — never bespoke MAVLink sends from the swap executor.
enum MissionRunReserveSwapReplacedActiveFleetWindDownPolicy: Sendable {

    /// Dispatch shapes are always ``MissionRunFleetDispatch`` (``MissionRunFleetDispatch/preferentialCompleteTacticDispatch``,
    /// ``MissionRunFleetDispatch/preferentialReserveSwapTacticDispatch``,
    /// ``MissionRunFleetDispatch/preferentialAbortTacticDispatch``, move-point-park recipes, mission-clear atoms) matching
    /// ``MissionRunExecutionSubsystem`` / ``MissionRunPlannerSubsystem`` builders.
    static let useMissionControlCatalogueAndRecipeDispatchOnly = true

    /// For an **orderly** handoff (reserve takes the vacancy; old active still needs RTL / rally / loiter / park),
    /// prefer ``MissionRunPolicyResolution/resolvedReserveSwapPreferenceChain`` (or, when a single recovery surface is
    /// intentional, ``MissionRunPolicyResolution/resolvedCompletePreferenceChain``) and
    /// ``MissionRunExecutionSubsystem/buildCompletePolicyWindDownCommands(limitedToAssignmentIDs:)`` scoped to the
    /// **assignment row that still owns the replaced fleet token** (e.g. pool berth / `.reserve` roster), **not** the
    /// vacancy row (which now carries the reserve token after commit).
    static func preferCompletePreferenceWindDownForOrderlySwapOut(_ orderly: Bool) -> Bool { orderly }

    /// Immediate stop-class wind-down (treat swap-out like abort) uses the same stack as whole-run abort: mission clear
    /// first where applicable, then ``MissionRunPolicyResolution/resolvedAbortPreferenceChain`` via
    /// ``MissionRunPlannerSubsystem/buildAbortPlan`` execution paths — **not** a parallel command catalogue.
    static let abortClassWindDownUsesAbortPlanStack = true
}

// MARK: - Telemetry + MC-R focus

/// **UI / map** contract while the replaced **vehicle** is still airborne or hub-linked.
enum MissionRunReserveSwapReplacedActiveTelemetryHandoffPolicy: Sendable {

    /// After swap, Mission Control running surfaces should foreground the **vacancy** stream (new active on task) for
    /// triage and primary map follow — without removing the replaced **vehicle** from the fleet map.
    static let focusMissionControlRunningOnVacancyAssignmentFirst = true

    /// The replaced **vehicle** remains an ordinary fleet/map participant until orderly wind-down completes, RTL / park
    /// finishes, or hub link loss removes it through existing fleet lifecycle rules — roster mutation alone does not
    /// hide the asset from the operator map.
    static let retainReplacedVehicleOnMapUntilWindDownCompletesOrLinkLost = true
}

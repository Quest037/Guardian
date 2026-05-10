import Foundation

// MARK: - Risk tier (live-mission policy)

/// How a command relates to the live-mission gate. Used by Layer 1 recipe runners and
/// Layer 2 process surfaces to decide whether to allow / require-confirmation /
/// silently permit dispatch on a vehicle currently bound to a `.running` / `.paused` /
/// `.recovery` Mission Control run.
///
/// Layer 0 invocations do **not** enforce the tier themselves — the tier is metadata
/// for higher layers to honour. (See `MissionControlStore.preflightProbeReadinessBlocker`
/// for the existing equivalent at the preflight layer; recipes will reuse the same
/// `isVehicleStreamUsedInLiveMission` predicate.)
enum FleetCommandRiskTier: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    /// Must not be dispatched while the vehicle is in a live mission (compass swing,
    /// gyro cal, anything that touches calibration state or arming).
    case groundOnly
    /// Allowed in a live mission only after explicit operator confirmation
    /// (parameter writes, mode forces, GPS reacquire).
    case confirmInLiveMission
    /// Safe to dispatch in any state (telemetry reads, light advisory clears).
    case safeInLiveMission
}

// MARK: - Declared response kinds

/// Documents the closed set of `FleetCommandErrorKind` values a descriptor's stack
/// converters are allowed to produce, plus high-level shape (`success`, payload,
/// cancellable, can-time-out) flags.
///
/// Recipes that branch on `error.<kind>` should only match against kinds that appear
/// in the descriptor's declared set — converters are contracted to never produce a
/// kind they did not declare. The catalogue does not enforce this at runtime in v1
/// (the dynamic enum is closed enough that a typo would surface in code review), but
/// the declaration is the authoritative documentation for recipe authors.
struct FleetCommandDeclaredResponseKinds: Equatable, Hashable, Sendable {
    /// Whether the command can succeed (almost always `true`; `false` for purely
    /// diagnostic stubs).
    let canSucceed: Bool
    /// Closed set of error kinds the converters may return.
    let errorKinds: Set<FleetCommandErrorKind>
    /// Whether `command.get.*` reads return a non-empty payload on success.
    let producesPayloadOnSuccess: Bool
    /// Whether the command supports being cancelled mid-flight via
    /// ``FleetCommandsCatalogue/cancel(invocationID:)`` (Stage B work).
    let isCancellable: Bool
    /// Whether the command can terminate with `.timeout`.
    let canTimeout: Bool

    /// Sensible default for a one-shot `do.*` command: succeeds, can fail with a small
    /// set of routing kinds, no payload, not cancellable, can time out.
    static let standardDo: FleetCommandDeclaredResponseKinds = FleetCommandDeclaredResponseKinds(
        canSucceed: true,
        errorKinds: [
            .noVehicle, .notConnected, .noSession, .authorityGated,
            .notImplemented, .dispatchFailed, .unknown
        ],
        producesPayloadOnSuccess: false,
        isCancellable: false,
        canTimeout: true
    )

    /// Sensible default for a `get.*` read.
    static let standardGet: FleetCommandDeclaredResponseKinds = FleetCommandDeclaredResponseKinds(
        canSucceed: true,
        errorKinds: [
            .noVehicle, .notConnected, .notImplemented, .dispatchFailed, .unknown
        ],
        producesPayloadOnSuccess: true,
        isCancellable: false,
        canTimeout: false
    )

    /// Sensible default for a `cancel.*` command.
    static let standardCancel: FleetCommandDeclaredResponseKinds = FleetCommandDeclaredResponseKinds(
        canSucceed: true,
        errorKinds: [
            .noVehicle, .notConnected, .noSession, .notImplemented, .dispatchFailed, .unknown
        ],
        producesPayloadOnSuccess: false,
        isCancellable: false,
        canTimeout: true
    )

    /// Strictly extends a base set with extra error kinds. Useful to keep registrations
    /// terse — `.standardDo.adding(.alreadyArmed, .calibrationDeclined)` etc.
    func adding(_ extras: FleetCommandErrorKind...) -> FleetCommandDeclaredResponseKinds {
        FleetCommandDeclaredResponseKinds(
            canSucceed: canSucceed,
            errorKinds: errorKinds.union(extras),
            producesPayloadOnSuccess: producesPayloadOnSuccess,
            isCancellable: isCancellable,
            canTimeout: canTimeout
        )
    }
}

// MARK: - Retry hints

/// Suggested retry policy for a command. The catalogue does **not** retry on its own
/// (Layer 0 is single-shot); recipes (Layer 1) consume these hints when authoring a
/// `retry: { count, delay }` block on a step.
struct FleetCommandRetryHints: Equatable, Hashable, Sendable, Codable {
    let suggestedMaxRetries: Int
    let suggestedDelaySeconds: Double

    static let none = FleetCommandRetryHints(suggestedMaxRetries: 0, suggestedDelaySeconds: 0)
    static let conservative = FleetCommandRetryHints(suggestedMaxRetries: 2, suggestedDelaySeconds: 1.0)
    static let aggressive = FleetCommandRetryHints(suggestedMaxRetries: 4, suggestedDelaySeconds: 0.5)
}

// MARK: - Descriptor

/// Full metadata for a command registered in ``FleetCommandsCatalogue``.
///
/// **Composition rule (v1):** ``containsCommands`` may list other registered command
/// names that this command expands into when invoked. The expansion is **strictly one
/// level deep** — registered children must themselves have an empty `containsCommands`
/// list. The catalogue rejects deeper nesting at registration time.
struct FleetCommandDescriptor: Equatable, Sendable {

    let name: FleetCommandName
    /// Human-facing one-liner.
    let humanLabel: String
    /// Longer human-facing description; safe to surface in tooltips, recipe authoring docs.
    let humanDescription: String
    /// Parameter schema (may be empty).
    let parameters: [FleetCommandParameterDeclaration]
    /// Documents the closed response shape for this command.
    let declaredResponseKinds: FleetCommandDeclaredResponseKinds
    /// Suggested retry hints for recipe authors.
    let retryHints: FleetCommandRetryHints
    /// Live-mission gate policy; honoured by Layer 1+, not by the raw `invoke()`.
    let riskTier: FleetCommandRiskTier
    /// One-level command-contains-command composition. Empty for atomic commands.
    let containsCommands: [FleetCommandName]
    /// Plugin owner, when contributed by a plugin. `nil` for core registrations.
    let pluginID: GuardianPluginID?

    init(
        name: FleetCommandName,
        humanLabel: String,
        humanDescription: String,
        parameters: [FleetCommandParameterDeclaration] = [],
        declaredResponseKinds: FleetCommandDeclaredResponseKinds,
        retryHints: FleetCommandRetryHints = .none,
        riskTier: FleetCommandRiskTier,
        containsCommands: [FleetCommandName] = [],
        pluginID: GuardianPluginID? = nil
    ) {
        self.name = name
        self.humanLabel = humanLabel
        self.humanDescription = humanDescription
        self.parameters = parameters
        self.declaredResponseKinds = declaredResponseKinds
        self.retryHints = retryHints
        self.riskTier = riskTier
        self.containsCommands = containsCommands
        self.pluginID = pluginID
    }

    /// `true` when this descriptor expands into other registered commands.
    var isComposite: Bool { !containsCommands.isEmpty }
}

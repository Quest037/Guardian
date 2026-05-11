import Foundation

// MARK: - Risk tier (live-mission policy)

/// How a recipe relates to the live-mission gate.
///
/// Mirrors ``FleetCommandRiskTier`` as a sibling so the recipe runner can enforce a
/// recipe-wide tier without conflating it with the per-command tier. A composite
/// recipe declares its own tier; the runner uses the strictest of (a) the recipe's
/// declared tier and (b) the strictest tier among the commands it invokes.
enum FleetRecipeRiskTier: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    /// Must not be dispatched while the vehicle is in a live mission (compass swing,
    /// gyro cal, anything that touches calibration state or arming).
    case groundOnly
    /// Allowed in a live mission only after explicit operator confirmation.
    case confirmInLiveMission
    /// Safe to dispatch in any state (telemetry-read recipes, light advisory clears).
    case safeInLiveMission
}

// MARK: - Descriptor

/// Full metadata for a recipe registered in ``FleetRecipesCatalogue``.
///
/// **Composition rule (v1):** ``containsRecipes`` may list other registered recipe
/// names that this recipe expands into when run. The expansion is **strictly one
/// level deep** — registered children must themselves have an empty `containsRecipes`
/// list. The catalogue rejects deeper nesting at registration time so we never have
/// to detect cycles or unbounded depth at run time. This mirrors the locked decision
/// for Layer 0 (`command → command`, also one level).
///
/// **The descriptor only carries metadata.** The actual recipe body — the step list,
/// branching, escalation contract — lives in the DSL payload that Stage B1 → item 3
/// will introduce. The descriptor is the registration handle.
struct FleetRecipeDescriptor: Equatable, Sendable {

    let name: FleetRecipeName

    /// Human-facing one-liner.
    let humanLabel: String

    /// Longer human-facing description; safe to surface in tooltips and authoring
    /// docs.
    let humanDescription: String

    /// Parameter schema (may be empty).
    let parameters: [FleetRecipeParameterDeclaration]

    /// Live-mission gate policy honoured by the recipe runner.
    let riskTier: FleetRecipeRiskTier

    /// Optional expected wall-clock duration for the happy path. Surfaces in UI
    /// progress hints; not enforced as a hard cap (that's the recipe overall budget,
    /// declared in the DSL).
    let expectedDuration: TimeInterval?

    /// Other recipes that must succeed first when this recipe runs as part of a
    /// flow. v1 stores these as metadata; Stage B1 → item 4 (runner) will consult
    /// them. Cycles are prevented by composition-depth enforcement at the catalogue
    /// level, not by prerequisite chasing.
    let prerequisites: [FleetRecipeName]

    /// Telemetry-catalogue system labels this recipe applies to (e.g. `"compass"`,
    /// `"battery"`). Free-form string keys today; Stage C tightens this against the
    /// telemetry catalogue's directory shape.
    let appliesToSystems: [String]

    /// Default retry policy applied to steps in this recipe when the step itself
    /// declares none. The catalogue's hard caps (``FleetRecipeRetryPolicy/maxAttemptsCap``
    /// etc.) are enforced against this value at registration time unless
    /// ``relaxRetryCaps`` is set.
    let defaultRetryPolicy: FleetRecipeRetryPolicy

    /// Opt-out for the catalogue retry-policy hard caps.
    ///
    /// When `true`, ``FleetRecipesCatalogue`` logs the offending policy as a warning
    /// but still registers the descriptor. Reserved for rare recipes whose authors
    /// have an explicit reason to need longer retries / more attempts (e.g. a
    /// plugin probing a flaky third-party radio). v1 standing rule: do **not** set
    /// this without code review.
    let relaxRetryCaps: Bool

    /// Plugin owner, when contributed by a plugin. `nil` for core registrations.
    /// Stage F manifest namespace claims will use this together with ``name``'s
    /// namespace to enforce the publishing claim.
    let pluginID: GuardianPluginID?

    /// One-level recipe-contains-recipe composition. Empty for atomic recipes.
    let containsRecipes: [FleetRecipeName]

    /// Executable spec for this recipe. Optional so a descriptor can be registered
    /// without a body (Stage C lands descriptors and bodies independently; the
    /// runner refuses to start a body-less recipe). When set, the catalogue runs
    /// the body through ``FleetRecipeBodyParser/validate(_:against:registry:)``
    /// at registration time and rejects the descriptor on any structural error.
    let body: FleetRecipeBody?

    /// Optional cleanup recipe run by the runner when this recipe is cancelled
    /// mid-flight. The runner aborts the current step, then dispatches this
    /// recipe with no parameters before reporting the parent run as `failed`
    /// with `detail: "cancelled"`. v1 supports **one cleanup recipe per parent**;
    /// per-step cleanup hooks are a Stage B2 follow-up.
    ///
    /// Registration rule (mirrors ``containsRecipes``): the cancel recipe must
    /// already be registered when this descriptor registers, and it must itself
    /// be atomic (no cleanup of cleanup, no composite cleanup) — the catalogue
    /// rejects the registration otherwise.
    let cancelRecipe: FleetRecipeName?

    init(
        name: FleetRecipeName,
        humanLabel: String,
        humanDescription: String,
        parameters: [FleetRecipeParameterDeclaration] = [],
        riskTier: FleetRecipeRiskTier,
        expectedDuration: TimeInterval? = nil,
        prerequisites: [FleetRecipeName] = [],
        appliesToSystems: [String] = [],
        defaultRetryPolicy: FleetRecipeRetryPolicy = .catalogueDefault,
        relaxRetryCaps: Bool = false,
        pluginID: GuardianPluginID? = nil,
        containsRecipes: [FleetRecipeName] = [],
        body: FleetRecipeBody? = nil,
        cancelRecipe: FleetRecipeName? = nil
    ) {
        self.name = name
        self.humanLabel = humanLabel
        self.humanDescription = humanDescription
        self.parameters = parameters
        self.riskTier = riskTier
        self.expectedDuration = expectedDuration
        self.prerequisites = prerequisites
        self.appliesToSystems = appliesToSystems
        self.defaultRetryPolicy = defaultRetryPolicy
        self.relaxRetryCaps = relaxRetryCaps
        self.pluginID = pluginID
        self.containsRecipes = containsRecipes
        self.body = body
        self.cancelRecipe = cancelRecipe
    }

    /// `true` when this descriptor expands into other registered recipes.
    var isComposite: Bool { !containsRecipes.isEmpty }

    /// `true` when the descriptor's body contains at least one `.invokeRecipe`
    /// step. Used by the parser's 1-level depth check.
    var bodyInvokesAnyRecipe: Bool {
        guard let body else { return false }
        return body.steps.contains(where: { step in
            if case .invokeRecipe = step { return true }
            return false
        })
    }
}

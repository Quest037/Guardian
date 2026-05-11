# Commands & Recipes — Layered Architecture To-Do

Forward-looking tracker for the multi-stage build of the Fleet
**Commands → Recipes → Processes** architecture. Companion to `TODO.md`.

The locked layer model, source layout, conventions, retry / parser / depth
rules, and extension points live in `README.md` ("Fleet Commands & Recipes
architecture"). This file only tracks **what's still to do**.

---

## Stage D — Operator prompt channel (new infrastructure)

Status: building blocks complete (`OperatorPromptEvent` + `OperatorPromptTarget` +
`OperatorPromptOption` + `OperatorPromptAnswer`; delivery-target catalogue;
`ProcessPromptPolicy`; `OperatorPromptRouter`; `OperatorPromptResumptionChannel`).
All documented in `README.md` under "Operator-prompt …" sections.

The remaining integration — the stateful `OperatorPromptCenter` that wraps the
building blocks with host registration, dispatch / mirror withdrawal, the
per-event expiry timer, and the `publish(_:) async -> Answer` convenience API —
lands during Stage E wizard wiring, alongside the first real delivery surfaces.
Until then publishers can be written against `OperatorPromptResumptionChannel`
directly and route via `OperatorPromptRouter.shared.route(_:)`.

## Stage E — Operator wizard process in Vehicle Inspector

Goal: replace today's hardcoded calibration/preflight buttons with a directory-driven
wizard process that runs recipes, renders progress, and resolves escalations inline.

- [ ] Replace per-system buttons with a single wizard launcher per recipe entry in the directory.
- [ ] Wizard renders: progress (step N of M), running command, prompts, resumption verbs.
- [ ] Wizard consumes Layer 2 escalation events; surfaces `rotate drone` etc. inline.
- [ ] Preflight migrates to `recipe.fleet.diagnose.armProbe` (no special path).
- [ ] Generalise `PreflightProbeHistoryEntry` → `RecipeRunHistoryEntry` (cap retained, source field kept).
- [ ] FVM holds unified recipe-run history; preflight overlay still works because preflight is a recipe.
- [ ] Live-mission gate respected at wizard entry (`Preflight locked` pattern generalises to `Recipe locked`).
- [ ] Vehicle Inspector marker overlay updates live during recipe runs.
- [ ] Cancel action wired to runner's `cancel(runID)` and translated to vehicle-side cancel where defined.
- [ ] Document: wizard contract for operators, integration points for other surfaces (MCR, LiveDrive).

## Stage F — Plugin manifest namespace claims

Goal: plugins declare which command/recipe namespaces they publish and invoke; the
registry enforces both directions.

- [ ] Extend `GuardianPluginManifest` with `publishedCommandNamespaces`, `publishedRecipeNamespaces`.
- [ ] Extend manifest with `invokedCommandNamespaces`, `invokedRecipeNamespaces`.
- [ ] `GuardianPluginBootstrap` validates claims against `GuardianPluginID` namespace prefix rules.
- [ ] `FleetCommandsCatalogue` and `FleetRecipesCatalogue` reject contributions outside the publishing claims.
- [ ] Invocation paths (runner, registry dispatch) check invoker's invoked-namespace claims.
- [ ] Paladin acts as the worked example (no real recipes yet — just a manifest claim test).
- [ ] Document: plugin contribution guide — namespace claims, JSON contribution layout.

## Stage G — Tests (runs alongside every stage)

Goal: confidence that the layers behave deterministically, that the response taxonomy
covers the real ArduPilot/PX4 outcomes, and that the runner's failure modes are
exhaustively covered.

- [ ] Unit: response taxonomy mappings per stack.
- [ ] Unit: command catalogue registration validation (namespaces, claims).
- [ ] Unit: recipe DSL parser — valid + malformed JSON cases.
- [ ] Unit: recipe runner branching, retry counts, escalate paths, cancel semantics.
- [ ] Unit: composition depth enforcement (1-level limit for both layers).
- [ ] Unit: live-mission gate enforcement on recipe entry.
- [ ] Unit: audit log per-step trace + failing-command path on failure.
- [ ] Integration (SITL both stacks): `recipe.fleet.calibrate.compass` end-to-end.
- [ ] Integration (SITL both stacks): `recipe.fleet.calibrate.accelerometer` end-to-end.
- [ ] Integration (SITL both stacks): `recipe.fleet.calibrate.gyro` end-to-end.
- [ ] Integration (SITL both stacks): `recipe.fleet.calibrate.baro` end-to-end.
- [ ] Integration (SITL both stacks): `recipe.fleet.calibrate.level` end-to-end.
- [ ] Integration (SITL both stacks): `recipe.fleet.diagnose.armprobe` (preflight equivalent).
- [ ] Integration (SITL both stacks): `recipe.fleet.errors.fix.calibrationrequired`
  composes through to a green-state recovery.
- [ ] Integration: cancel mid-recipe; verify vehicle-side cancel ran where declared.
- [ ] Integration: escalation event routing through prompt channel (Stage D).

---

## Deferred / Out of Scope (this build)

- MRE planner → recipe-executor morph. Future milestone.
- `subscribe` verb. Existing telemetry pipes suffice for now.
- Cross-system bus extensions: `command.mc.*`, `command.plugin.*` outside Fleet.
- Partial-success recipe outcomes.
- Recursive composition beyond one level either side.
- New plugin permission model beyond manifest namespace claims.
- Auto-discovered recipe dependencies / graph view for plugins.

## Open Design Questions (decide before their stage starts)

- **Stage C:** which calibration recipes are pure-vehicle (no operator action) vs which
  require escalation steps? Answered **per recipe** during authoring — each per-recipe
  bullet above commits its own answer when it lands.
- **Stage D:** does the prompt router live in the App layer (alongside `withToasts`,
  `withAppDrawer`) or in a Fleet subsystem? Probably App layer because LiveDrive
  and MCR both need it.
- **Stage E:** wizard UI placement — keep inside Vehicle Inspector modal, or extract a
  reusable `RecipeWizardOverlay` that MCR / LiveDrive can use too?
- **Stage F:** are namespace claims fail-closed (plugin won't load if a claim is invalid)
  or fail-open with warnings? Probably fail-closed for publish, warn-then-skip for invoke.

## Cross-References (existing TODO.md entries that this work absorbs)

- `## Vehicles System → Vehicle Calibration → Catalogue of calibration methods` →
  becomes the recipe catalogue under `Subsystems/Calibration/`.
- `## Vehicles System → Vehicle Calibration → Manual Calibration Process (live + sim)` →
  becomes the operator wizard process in Stage E.
- `## Vehicles System → Vehicle Preflight → Attempt to arm, get errors and utilise
  calibration catalogue to solve` → becomes `recipe.fleet.diagnose.armProbe` chained
  to `recipe.fleet.errors.fix.*` recipes once the Errors subsystem has content.
- `## Vehicles System → Vehicle Preflight → Live-mission preflight override surfaces` →
  generalises to "live-mission recipe override surfaces" once recipes are the unit of work.
- `### Commands Catalogue → Commands → Build more generic / specific commands` →
  becomes new `command.fleet.vehicle.do.*` registrations + composing recipes.
- `### Commands Catalogue → Stack Converters → PX4 / AP` → expanded with calibration,
  error-clear, telemetry-get verbs and the normalised response taxonomy.
- `## App System → UserNotifications` → integrated as one of the prompt-channel
  delivery targets in Stage D.
- `## Plugins System → Registry → Fix up how plugins register to extend the app` →
  satisfied (in part) by Stage F namespace claims.

## Status Legend

- `[ ]` not started
- `[x]` completed
- `[~]` in progress (use sparingly; prefer breaking into smaller items)
- `[!]` blocked — note blocker inline

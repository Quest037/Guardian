# Commands & Recipes — Layered Architecture To-Do

Living tracker for the multi-stage build of the Fleet **Commands → Recipes → Processes**
architecture. This is **not** a one-pass change; each stage ships and is reviewed standalone.
Companion to `TODO.md`.

## Architectural Model (locked)

Three strict layers, top → bottom:

- **Layer 2 — Processes (visible drivers).** Operator wizard, MCR headless, plugin
  headless, LiveDrive. Run recipes, route escalations to the right operator-prompt
  channel based on a process-declared fallback list.
- **Layer 1 — Recipe catalogues (per Fleet subsystem).** Calibration, Errors. Recipes
  are JSON-authored declarative state machines: issue command → branch on response →
  retry / escalate / continue. Knows nothing about operators or UI.
- **Layer 0 — Commands catalogue (core-owned).** `command.do.* / command.get.* /
  command.cancel.*`. Atomic, stack-translated, returns a normalised typed response.
  No knowledge of humans, recipes, missions, plugins.

Direct `command.*` invocation is allowed but discouraged; every real flow goes through a
recipe so response handling, branching, retries, escalation, and audit trail come for free.

## Locked Decisions

- **Reserved verbs:** `do`, `get`, `cancel` only. `subscribe` deferred.
- **Composition depth:** recipe → recipe (1 level), command → command (1 level). Max
  shape `recipe → recipe → command → command`. No deeper recursion; no cycle detection
  needed because depth is bounded.
- **Recipe outcome:** binary — `succeeded` or `failed`. Failure surfaces the failing
  command path. No partial-success outcomes.
- **JSON-first authoring** for portability across macOS / Linux / Windows. Swift escape
  hatch only when the DSL genuinely cannot express a flow.
- **Telemetry catalogue is a directory, not an owner.** Each system entry references
  recipe paths; the recipes themselves live in their Calibration / Errors subsystem
  catalogues.
- **Plugin contributions** plug into the existing `GuardianPluginRegistry` /
  `GuardianPluginBootstrap` pattern. Plugins extend Layer 1 and Layer 2. They do **not**
  register `command.*` entries except in the rare custom-comms exception
  (`command.do.<plugin>.*`).
- **MRE morph (planner → recipe executor)** is **out of scope**. Design Layer 1 with
  MRE's eventual needs in mind so we don't paint ourselves into a corner, but do not
  migrate MRE in this build.
- **Scope of universal bus:** v1 is `command.fleet.*` only. Extensions to
  `command.mc.*`, `command.plugin.*` are deferred.
- **Live-mission gate** stays the same primitive shipped today; recipes declare a risk
  tier that the runner enforces using the existing gate.

---

## Stage A — Closed: Layer 0 foundations (Commands catalogue)

Stage A established the Layer 0 registry shape, command naming, typed responses,
parameter schema, stack-converter protocol, bootstrap path, telemetry gets, the
expanded calibration command surface, command-level unit tests, and the opt-in SITL
smoke harness (see `scripts/run_sitl_smoke_tests.sh` / README).

Standing rule for later stages: do not treat a registered descriptor as "done" unless
the stack converter either performs a real, verifiable action or returns a deliberate,
documented `.notImplemented` because the required transport is genuinely unavailable.

## Stage B — Layer 1 foundations (Recipes catalogue + runner)

Goal: a registry-shaped `FleetRecipesCatalogue` with a JSON DSL, a deterministic
runner, and the escalation contract that Layer 2 will consume.

### Stage B1 — Recipe catalogue foundations

- [ ] Create `FleetRecipesCatalogue` registry (subsystem-extensible, plugin-bootstrap pattern).
- [ ] Define namespace validator: `recipe.<subsystem>.<segments>`; same rules as commands.
- [ ] Define recipe JSON DSL:
  - items: `invokeCommand(name, params, retry, onResponse)` and `invokeRecipe(name, params, onResponse)`
  - response matchers: `success | error.<kind> | data(predicate) | timeout | cancelled`
  - control: `branch`, `escalate(reason, allowedVerbs)`, `succeed`, `fail(failingPath)`
- [ ] Implement `FleetRecipeRunner`:
  - per-vehicle execution thread
  - response-driven step machine
  - cancel API: aborts current command, runs `recipe.<>.cancel.*` where declared
  - timeout per step, total recipe budget
  - audit-traced (per-step trace; failing-command path on failure)
- [ ] Define escalation contract carried to Layer 2:
  - `reason: { operatorActionRequired(.kind) | unrecoverableFailure(.kind) | confirmation(.kind) }`
  - last response payload
  - allowed resumption verbs: `acknowledge`, `retry`, `skip`, `abort`
- [ ] Recipe metadata: risk tier, expected duration, prerequisites, applies-to systems.
- [ ] Runner enforces live-mission risk tier via existing gate primitive.
- [ ] Recipe outcome is binary: `succeeded` or `failed(failingCommandPath, lastResponse)`.
- [ ] Recipe contains recipe at exactly one nesting level; hard-fail at parse on deeper nesting.
- [ ] Document: DSL spec, runner state machine, escalation contract, audit shape.

## Stage C — Calibration + Errors subsystems + telemetry directory

Goal: the first content layer — calibration recipes that exercise Layer 1 against real
ArduPilot and PX4 SITL — and the telemetry catalogue surfacing them as a directory.

- [ ] Create `Sources/GuardianHQ/Systems/Fleet/Subsystems/Calibration/`:
  - JSON catalogue file
  - subsystem registration entry point
  - bootstrap into `FleetRecipesCatalogue` and (where needed) `FleetCommandsCatalogue`
- [ ] Author calibration recipes:
  - `recipe.fleet.calibrate.compass`
  - `recipe.fleet.calibrate.accelerometer`
  - `recipe.fleet.calibrate.gyro`
  - `recipe.fleet.calibrate.baro`
  - `recipe.fleet.calibrate.level`
- [ ] Each recipe declares risk tier (most are `groundOnly` for v1).
- [ ] Each recipe declares expected escalation kinds (e.g. `rotateDrone`, `holdStill`).
- [ ] Author `recipe.fleet.diagnose.armProbe` — the migration target for current preflight.
- [ ] Create `Sources/GuardianHQ/Systems/Fleet/Subsystems/Errors/` scaffold:
  - empty catalogue in v1, with the registration shape proven
  - placeholder for first error-fix recipe so the wiring is testable
- [ ] Subsystems self-register at app boot (idempotent, no double-registration).
- [ ] Extend `FleetTelemetryFieldCatalog`:
  - per-system: `recipes.calibrate: [path]`, `recipes.errorFix: [path]`
  - directory entries reference recipes by path; do **not** own them
  - telemetry case is the convenience index for processes; not the source of truth
- [ ] Vehicle Inspector reads the directory to render per-system action menus
  (no hardcoded buttons per system).
- [ ] Document: recipe authoring guide for each subsystem, telemetry directory shape.

## Stage D — Operator prompt channel (new infrastructure)

Goal: a unified, routeable operator-prompt channel so any process can escalate without
inventing its own delivery path. Driven by the escalation contract from Stage B.

- [ ] Audit `MissionRunEnvironment` Rules of Engagement seeds for prompt concepts already in code.
- [ ] Define `OperatorPromptEvent` type mirroring escalation contract payload.
- [ ] Define delivery targets:
  - MCR prompt panel
  - Persistent toast
  - UserNotifications (incl. "get back to MCR" alert variant)
  - LiveDrive prompt
  - Vehicle Inspector wizard prompt
- [ ] Define `ProcessPromptPolicy`: ordered fallback list per process context.
- [ ] Implement router: pick target by policy + current operator presence/context.
- [ ] Resumption verbs flow back through router to the runner that emitted the event.
- [ ] **Stage D needs its own design pass before any code lands** — this is genuinely
      new infrastructure, not just plumbing.
- [ ] Document: prompt event shape, target catalogue, fallback semantics.

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
- [ ] Integration (ArduPilot SITL): `recipe.fleet.calibrate.compass` end-to-end.
- [ ] Integration (PX4 SITL): `recipe.fleet.calibrate.compass` end-to-end.
- [ ] Integration (ArduPilot SITL): `recipe.fleet.diagnose.armProbe` (preflight equivalent).
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

- **Stage B:** parameter schema format — Codable Swift types, JSON Schema, or a small
  custom validator? Affects how plugins author parameter validation.
- **Stage B:** retry backoff policy default — fixed delay, exponential, or per-recipe declared?
- **Stage C:** which calibration recipes are pure-vehicle (no operator action) vs which
  require escalation steps? Drives the recipe count and the escalation kinds inventory.
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

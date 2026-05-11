# Guardian

Guardian is now a native macOS app shell built with SwiftUI.

## Current app shell

- Dark-first HQ interface
- Left navigation: `Dashboard`, `Devices`, `Missions`, `Mission Control`
- Top bar with app title
- Per-page content title/subtitle so navigation changes are obvious

## Build and run

From the `Guardian` directory (SwiftPM):

```bash
swift build
swift run GuardianHQ
```

Or use the Makefile (also fetches bundled `mavsdk_server` on first build), then run the binary SwiftPM emitted (path varies by architecture):

```bash
make build
"$(swift build --show-bin-path)/GuardianHQ"
```

Open the package in Xcode if you prefer:

```bash
open Package.swift
```

Then **Product → Run** (⌘R). Xcode uses the same SwiftPM target.

### Optional one-time dependencies (SITL / bridge)

- **ArduPilot SITL bundle:** `make sitl-runtime` — Python for `sim_vehicle`: `make sitl-deps`
- **PX4 SITL runtime slice** (`bin/px4` + `etc/`): build PX4 elsewhere, then `PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot make px4-sitl-runtime`
- **Prewarm both SITL stacks:** `make sitl-prewarm` (ArduPilot full prebuild), or include PX4 too: `PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot make sitl-prewarm`
- **MAVSDK-Python bridge:** `make bridge-deps`

## SITL command-catalogue smoke tests

End-to-end coverage for the Layer 0 fleet command catalogue (`command.fleet.vehicle.*`) ships as an **opt-in** XCTest suite, `GuardianHQSitlSmokeTests` in `Tests/GuardianHQTests/`. It is not part of normal `swift test` runs because it boots real **ArduPilot** and **PX4** SITL instances, starts `mavsdk_server` sessions, and drives the real `SitlService` → `FleetLinkService` → `FleetCommandsCatalogue` path against them.

### Run the suite

The canonical entry point is the repo script:

```bash
scripts/run_sitl_smoke_tests.sh
```

The script sets `GUARDIAN_RUN_SITL_SMOKE=1` and filters `swift test` to the smoke suite. Without that env var, the tests `XCTSkip` themselves so `swift test` (CI, dev loop) stays fast and deterministic.

Prerequisites are the same as for in-app SITL: bundled ArduPilot tree (`make sitl-runtime` or developer checkout via `GUARDIAN_ARDUPILOT_ROOT`), PX4 SITL slice (`make px4-sitl-runtime` or `GUARDIAN_PX4_ROOT` pointing at a PX4-Autopilot checkout with `px4_sitl_default` already built), and the SITL Python deps (`make sitl-deps`).

### What it covers

In one shared session per stack, for both ArduPilot and PX4:

- **Telemetry reads** — every `get.telemetry.*` descriptor returns a populated `keyValues` payload.
- **Param-set calibration** — `do.calibrate.battery.capacity` round-trips through the catalogue's `PARAM_SET` + read-back path.
- **Set-mode** — `do.mode mode=hold` succeeds and the autopilot's reported flight mode flips to a hold/loiter token.
- **Arm / disarm** — `do.arm` succeeds once the vehicle reports `healthArmable`, telemetry transitions to armed, then `do.disarm` brings it back down.
- **Loiter / return-home / land** — `do.loiter`, `do.return.home`, and `do.land` are accepted by the autopilot after re-arm.
- **PX4 calibration plugin** (PX4 only) — `do.calibrate.{gyro, level, gimbal}` exercises the MAVSDK Calibration plugin transport and surfaces a non-transport outcome (success, declined, did-not-converge, busy, etc.).

### Tuning timeouts

The harness honours these environment variables when set; otherwise it uses the defaults shown:

| Variable | Default (s) | Used for |
| --- | --- | --- |
| `GUARDIAN_SITL_SMOKE_BOOT_TIMEOUT` | `180` | Waiting for each SITL session to reach `.live` and for `healthArmable`. |
| `GUARDIAN_SITL_SMOKE_COMMAND_TIMEOUT` | `45` | Per-command catalogue dispatch budget. |
| `GUARDIAN_SITL_SMOKE_SIDE_EFFECT_TIMEOUT` | `20` | Waiting for telemetry side-effects (armed state, mode change). |
| `GUARDIAN_SITL_SMOKE_CALIBRATION_TIMEOUT` | `90` | PX4 calibration plugin per-procedure budget. |

### Extending it

When you wire a new command in `FleetCommandsCatalogue`, add a matching smoke assertion to `GuardianHQSitlSmokeTests` (in the same shared-session loop) per the **Add Tests For New Features** rule. Use `invoke(...)` + `assertSuccess(...)` for happy-path commands, and `assertNoTransportFailure(...)` for procedures whose autopilot-side outcome is non-deterministic in SITL (e.g. calibration progress).

## SIM battery drain (SITL)

Guardian can **turn simulated pack depletion on or off** for built-in SITL vehicles from **LiveDrive** and **Mission Control → Running**, so operational flows see realistic battery movement instead of a static 100%. This is **stack-agnostic in the app** but implemented with **different autopilot parameters** and **different simulator rules** on the wire.

### Where to configure it

- **Settings → SIMs → Default SIM battery drain rate** — Slow / Normal / Fast. This is the **fallback rate** when LiveDrive or Mission Control Running enables drain (not a global “always on” switch).
- **LiveDrive** — When a **SIM** is selected, use the **cog** in the sub-bar to open **SIM Live Settings**: toggle drain for that vehicle, pick a rate, and **Apply**. The sidebar explains PX4 vs ArduPilot behavior at a glance.

### What Guardian sets

| Stack      | Parameter          | When drain is **on** | When drain is **off** |
| ---------- | ------------------ | -------------------- | --------------------- |
| **PX4**    | `SIM_BAT_DRAIN`    | Positive float: full-discharge time in **seconds** (while the vehicle is **armed** in stock PX4 SITL). | `0` (disables the timed drain model). |
| **ArduPilot** | `SIM_BATT_CAP_AH` | Positive float: simulated pack capacity (**Ah**) for the SITL battery integrator. | `0` (static / non-integrating model for that path). |

Successful writes appear in the fleet log as `Param set [source=…] …` for the vehicle; failures show as `Param set failed …`.

### Autopilot semantics (why it can still read “100%”)

These rules come from the **simulators**, not from Guardian skipping a step.

- **PX4** — Stock `BatterySimulator` **only runs the discharge timer while armed**. While **disarmed**, it **resets** the simulated state of charge toward **full**. So LiveDrive or MC-R with a disarmed PX4 SIM will often look stuck at 100% even though `SIM_BAT_DRAIN` is set.
- **ArduPilot** — SITL battery charge moves with **integrated current**. **Near-zero motor current** (disarmed or idle throttle) means **little or no** visible drop for a long time.

To validate the feature: **arm** a PX4 SIM (or apply meaningful throttle on ArduPilot) and watch battery telemetry; confirm params in the log if in doubt.

## SIM state on the wire (`FleetSimState` / `applySimState`)

Guardian routes **every** programmatic SIM pose/SIM-parameter reset through one API so spawn, Mission Control‑E (MC‑E), and future “SIM recovery” actions stay aligned.

### Types

| Symbol | Location | Purpose |
| ------ | -------- | ------- |
| `FleetSimState` | `Sources/GuardianHQ/FleetSimState.swift` | Values to apply: lat/lon, optional AMSL-ish altitude, yaw, optional ArduPilot `SIM_BATT_*`, optional PX4 `SIM_BAT_DRAIN`. |
| `FleetLinkService.applySimState(vehicleID:state:autopilotStack:source:)` | `FleetLinkService.swift` | **Only** supported path to push those values to the autopilot over MAVSDK (built-in **Guardian SITL** streams only). |

Builders in use today:

- `FleetSimState(spawnDefaults:)` — mirrors **General → SIM spawn defaults** when reinforcing state after link-up (`source` typically `sitl.spawnHandshake`).

Other call sites build `FleetSimState` manually (or add new `init` helpers) then call `applySimState`.

### Autopilot wiring (what gets set)

**ArduPilot SITL:** `SIM_OPOS_LAT`, `SIM_OPOS_LNG`, `SIM_OPOS_ALT`, `SIM_OPOS_HDG`; optionally `SIM_BATT_VOLTAGE`, `SIM_BATT_CAP_AH` when the `FleetSimState` carries values.

**PX4 SIH SITL:** `SIH_LOC_LAT0`, `SIH_LOC_LON0`, `SIH_LOC_H0`; optionally `SIM_BAT_DRAIN` when set on state.

Launch recipes (`SitlLaunchRecipe`) still pass **CLI/env seeds** (`sim_vehicle.py -l …`, `PX4_HOME_*`); after MAVSDK reports **connected**, the spawn path schedules one `applySimState` (~0.5s delay) so Guardian and the autopilot agree on pose without duplicating unrelated launch logic in Swift.

### Guidance for Mission Control‑E (and agents)

When MC‑E (or tooling) needs to **teleport or reset SIM-facing params**:

1. Build a `FleetSimState` with the desired fields (reuse existing builders or populate manually).
2. Resolve `FleetAutopilotStack` for the vehicle (from fleet model / telemetry, same as other fleet code).
3. `await fleetLink.applySimState(vehicleID:vID, state:, autopilotStack:, source:"mc.phaseName")`.

Do **not** add parallel `setVehicleFloatParameter` call sites for the same SIM_OPOS / SIH_LOC family—extend `FleetSimState` / `applySimState` instead so UX and logs stay coherent.

## Live Drive control session (freestyle & mission, SIM & live)

While a Live Drive session is active, `FleetLinkService` sets **`liveDriveControlSessionVehicleID`** (`setLiveDriveControlSessionVehicle` / `clearLiveDriveControlSessionVehicleIfMatches`). Only that vehicle may receive **`liveDrive.*`** commands with **`.manualTakeover`** or run **manual control streaming** (`startManualControlStream`, `updateManualControlIntent`). This applies to **SIM and real aircraft**; **freestyle** and **mission** handoff both use the same gate (session kind is stored on `LiveDriveSessionRecord` for export). Param-only paths (e.g. SIM battery drain from the cog) are not gated by this.

## Fleet Commands & Recipes architecture

Guardian commands vehicles through a strict three-layer stack. This is the
authoritative reference for the layout, conventions, and extension points; the
in-progress work tracker lives in `CommandsRecipesToDo.md`.

### Layers (top → bottom)

| Layer | Owner | Responsibility |
| --- | --- | --- |
| **Layer 2 — Processes** | Operator wizard, MCR headless, plugin headless, LiveDrive | Run recipes; route escalations to the appropriate operator-prompt channel per a process-declared fallback policy. |
| **Layer 1 — Recipes (per Fleet subsystem)** | Calibration, Errors, Diagnose | JSON-authored declarative state machines: issue command → branch on response → retry / escalate / continue. Knows nothing about operators or UI. |
| **Layer 0 — Commands** | Core | Atomic, stack-translated commands in `command.do.* / command.get.* / command.cancel.*`. Each returns a normalised typed response. No knowledge of humans, recipes, missions, plugins. |

Direct `command.*` invocation is allowed but discouraged — every real flow goes through a recipe so response handling, branching, retries, escalation, and audit trail come for free.

### Source layout

- **Layer 0** — `Sources/GuardianHQ/Systems/Fleet/Subsystems/CommandsCatalogue/`
  - `FleetCommandName.swift` — `command.<addressing>.<verb>.<specifier>` validated identifier (verbs: `do | get | cancel`).
  - `FleetCommandResponse.swift` — closed outcome / error-kind / payload taxonomy.
  - `FleetCommandParameterSchema.swift` — parameter type kinds, declarations, validator.
  - `FleetCommandDescriptor.swift` — descriptor metadata: name, parameters, declared response kinds, retry hints, risk tier, composite `containsCommands`.
  - `FleetCommandsCatalogue.swift` — `@MainActor` registry singleton with `invoke(...)` pipeline.
  - `FleetCommandsCatalogueBootstrap.swift` — idempotent registration entry point.
  - `FleetCommandStackConverter.swift` + `Stacks/` — per-autopilot translation (`ArduPilot`, `PX4`, `Unknown`).
  - `Core/FleetVehicleCoreCommandRegistrations.swift` — core `command.fleet.vehicle.*` registrations.
- **Layer 1** — `Sources/GuardianHQ/Systems/Fleet/Subsystems/RecipesCatalogue/`
  - `FleetRecipeName.swift` — `recipe.<subsystem>.<specifier>` validated identifier (no verb segment).
  - `FleetRecipeParameterSchema.swift` — sibling of Layer 0's parameter validator.
  - `FleetRecipeRetryPolicy.swift` — policy struct + locked defaults + parser-time hard caps.
  - `FleetRecipeStepID.swift` — in-body author-chosen step identifier.
  - `FleetRecipePayloadPredicate.swift` — closed 8-kind predicate vocabulary (incl. `.stringMatches(regex:)`).
  - `FleetRecipeResponseMatcher.swift` — `success | error.<kind> | data(predicate) | timeout | cancelled | any`.
  - `FleetRecipeControlOutcome.swift` — `continue | branch | retry | succeed | fail | escalate`.
  - `FleetRecipeEscalation.swift` — escalation reason kinds (string-backed, extensible) + closed resumption-verb set.
  - `FleetRecipeStep.swift` + `FleetRecipeBody.swift` — `invokeCommand` / `invokeRecipe` steps, ordered body, entry step, overall budget.
  - `FleetRecipeBodyParser.swift` — JSON decode + structural validation (all errors surfaced in one pass).
  - `FleetRecipeDescriptor.swift` — descriptor with optional `body: FleetRecipeBody?` and optional `cancelRecipe: FleetRecipeName?` cleanup hook.
  - `FleetRecipesCatalogue.swift` + `FleetRecipesCatalogueBootstrap.swift` — singleton registry + idempotent entry point.
  - `FleetRecipeRunID.swift` + `FleetRecipeAuditTrace.swift` + `FleetRecipeOutcome.swift` + `FleetRecipeEscalationEvent.swift` — runner support types.
  - `FleetRecipeRunner.swift` — `@MainActor` singleton runner: per-vehicle execution, step machine, retry / branch / escalate / cancel, audit trace.
  - `FleetRecipeBodyLoader.swift` — hybrid loader: resolves a per-recipe JSON body from a bundle resource and decodes via `FleetRecipeBodyParser`; subsystem `registerAll()` calls it with its own `bodiesSubdirectoryName` and `Bundle.module`.
- **Layer 1 subsystems** — each subsystem owns a sibling directory under `Sources/GuardianHQ/Systems/Fleet/Subsystems/` containing a `@MainActor` registrations entry point invoked once by `FleetRecipesCatalogueBootstrap` plus a uniquely-named per-recipe-bodies directory. Directory names must be unique inside the bundle because SPM flattens `.copy(<dir>)` resources to the bundle root. Today's subsystems:
  - `Calibration/FleetCalibrationRecipeRegistrations.swift` + `Calibration/CalibrationBodies/*.json` — calibration recipes (`recipe.fleet.calibrate.*`) plus the diagnose recipes (`recipe.fleet.diagnose.*`) that share the same bodies directory. The entry-point enum exposes `bodiesSubdirectoryName` (`"CalibrationBodies"`). Stage C ships **24 recipes** total — 22 calibrations spanning every `do.calibrate.*` command surface (see `Sources/GuardianHQ/Systems/Fleet/Subsystems/Calibration/CalibrationBodies/_AUTHORING.md` for the per-recipe breakdown): one atomic cleanup recipe (`recipe.fleet.calibrate.cancel`), eight Pattern-A interactive cals (`compass`, `accelerometer`, `gyro`, `baro`, `level`, `airspeed`, `esc`, `rc`/`rc.trim`), three Pattern-B stack-asymmetric cals with explicit `notImplemented → fail` matchers (`compass.motor`, `baro.temperature`, `gimbal`), three Pattern-C discoverability shells whose underlying converter paths are `notImplemented` in v1 (`rangefinder`, `flow`, `vision`), and six Pattern-D param-driven writes using caller→step parameter references (`compass.declination`, `battery.{voltage,current,capacity}`, `servo`, `gimbal.neutral`); plus 2 Pattern-E diagnose recipes — `recipe.fleet.diagnose.cancel` (best-effort disarm cleanup) and `recipe.fleet.diagnose.armprobe` (the arm → disarm probe that classifies the common autopilot refusal kinds; the migration target for today's preflight overlay).
  - `Errors/FleetErrorRecipeRegistrations.swift` + `Errors/ErrorBodies/*.json` — error-fix recipes (`recipe.fleet.errors.fix.*`). Ships **1 recipe** in Stage C: `recipe.fleet.errors.fix.calibrationrequired` — the first composite (invokeRecipe-bearing) recipe in the catalogue. Four sequential `invokeRecipe` steps drive a compass → accelerometer → gyro calibration sweep then verify with `recipe.fleet.diagnose.armprobe`; the recipe declares the four children in `containsRecipes` so the catalogue's depth check enforces 1-level composition in both directions. The entry-point enum exposes `bodiesSubdirectoryName` (`"ErrorBodies"`).
  - Both registration entry points are idempotent — calling `registerAll()` twice is a no-op by the catalogue's per-name overwrite rule, and the bootstrap's one-shot latch short-circuits subsequent `ensureRegistered()` calls.
- **Telemetry recipe directory** — `FleetTelemetryFieldCatalog.systemRecipes` is a per-`FleetCalibrationSystemID` map of the calibration + error-fix recipe names that act on each system. The Vehicle Inspector reads this to render per-system action menus instead of hard-coding buttons; selecting an entry resolves the name through `FleetRecipesCatalogue` and shows descriptor metadata, while Stage E owns actually running the recipe wizard. The directory references recipes by **name only**, so recipes themselves stay owned by their subsystem registrations. `FleetRecipesCatalogueBootstrap.ensureRegistered()` calls `FleetTelemetryFieldCatalog.validateRecipeReferences(against:)` after every subsystem has registered and logs a fault for any citation that didn't resolve — a typo in a directory entry fails at app start rather than at menu-render time. A miss is a soft failure (the inspector just skips the menu entry); the validator returns the misses sorted `(system, recipe)` so log output stays stable.
- **Recipe source-of-truth: hybrid.** Descriptor metadata (`FleetRecipeDescriptor` — name, human label, risk tier, retry policy, parameters, prerequisites, escalation expectations, `cancelRecipe`) is authored as a **Swift literal** inside the subsystem's `registerAll()` so the compiler enforces every field rename, type change, and namespace claim. Recipe **bodies** (steps, matchers, branches, escalation outcomes) live as **per-recipe JSON files** under that subsystem's bodies directory (e.g. `CalibrationBodies/<recipe.name>.json`), loaded by `FleetRecipeBodyLoader` (`Bundle.module` resource → `FleetRecipeBodyParser.decode(jsonData:)` → `Result<FleetRecipeBody, FleetRecipeBodyLoadError>`). Catalogue-level structural validation (matchers, branch targets, registered references, regex compile, budget caps, 1-level composition depth) still happens inside `FleetRecipesCatalogue.register(...)`. Subsystem `registerAll()` calls `FleetRecipeBodyLoader.load(...)` with its own `bodiesSubdirectoryName`, refuses the registration on load failure (logging the diagnostic), and otherwise attaches the loaded body to the Swift descriptor literal before calling `FleetRecipesCatalogue.shared.register(...)`. This keeps the iteration-heavy step graph data-only (and portable to a future cross-platform Fleet core) while compile-time safety still guards the small, stable metadata layer that catalogue validation depends on. Plugin contributions follow the same shape — Swift descriptor + uniquely-named JSON bodies directory.

### Layer 1 subsystem authoring checklist

Use this checklist when adding a new Fleet recipe subsystem or extending an existing one:

1. **Create the subsystem shell:** add `Sources/GuardianHQ/Systems/Fleet/Subsystems/<Subsystem>/`, a `@MainActor` `<Subsystem>RecipeRegistrations` entry-point enum, and a uniquely named bodies directory such as `<Subsystem>Bodies`. Add that bodies directory to `Package.swift` with `.copy(...)`; do not name it only `Bodies` because SwiftPM flattens copied resources to the bundle root.
2. **Register through bootstrap:** expose `registerAll()` and call it once from `FleetRecipesCatalogueBootstrap.ensureRegistered()`. Registration must be idempotent; repeated app startup hooks or tests should leave the same descriptor set.
3. **Author descriptor metadata in Swift:** every `FleetRecipeDescriptor` must declare `name`, `humanLabel`, `humanDescription`, `parameters`, `riskTier`, `expectedDuration` when useful, `prerequisites`, `appliesToSystems`, retry policy, optional `pluginID`, `containsRecipes`, loaded `body`, and optional `cancelRecipe`. Keep labels operator-readable and descriptions specific enough for the inspector / wizard.
4. **Author bodies in JSON:** one file per recipe named `<recipe.name>.json`, loaded by `FleetRecipeBodyLoader` with `recipeName.rawValue`. Bodies declare one `entryStepID`, a bounded `overallBudgetSeconds`, and ordered `invokeCommand` or `invokeRecipe` steps. Prefer data-only bodies; use Swift only when the DSL cannot express the flow.
5. **Match per stack deliberately:** when a command is supported on one stack and unavailable on another, add an explicit `error(notImplemented) -> fail` matcher with a clear detail before the final `any` matcher. Unsupported-stack behavior should never be an accidental fall-through.
6. **Choose escalation vs fail:** escalate only when a process or operator could reasonably resume (`rotateDrone`, `holdStill`, `confirmInLiveMission`, etc.). Fail for structural limits, unavailable transports, invalid parameters, read-back mismatch, authority gates, or states where retrying needs a different process decision.
7. **Wire telemetry directory entries:** recipes are surfaced by `FleetTelemetryFieldCatalog.systemRecipes`, keyed by `FleetCalibrationSystemID`, with separate `calibrate` and `errorFix` lists. The directory references recipe names only; ownership stays with the subsystem registration. Bootstrap validation logs any missing citations.
8. **Add tests with the feature:** cover registration idempotency, descriptor metadata, body structure, matcher ordering, composition depth, parameter references, telemetry-directory references, and runner behavior when the recipe changes execution semantics. Add SITL smoke coverage for stack-facing happy paths when practical.

### Bootstrap order

Both catalogues self-register at app start, in this order, from `GuardianHQApp.swift`:

```swift
GuardianPluginBootstrap.ensureRegistered()
FleetCommandsCatalogueBootstrap.ensureRegistered()
FleetRecipesCatalogueBootstrap.ensureRegistered()
```

All three are idempotent; adding new core / subsystem registrations is a matter of plugging into the appropriate bootstrap, not reordering app startup.

### Locked architectural decisions

These are baked into the validators / registries. Changing one is an explicit, reviewed decision.

| Decision | Value |
| --- | --- |
| Reserved Layer 0 verbs | `do`, `get`, `cancel` only; `subscribe` is deferred. |
| Composition depth | `recipe → recipe` at exactly **1 level**; `command → command` at exactly **1 level**. Max shape `recipe → recipe → command → command`. No cycle detection because depth is bounded. |
| Recipe outcome | Binary — `succeeded` **or** `failed(failingCommandPath, lastResponse)`. No partial-success. |
| Authoring format | JSON-first. Swift escape hatch only when the DSL genuinely cannot express a flow. |
| Telemetry catalogue role | **Directory only**, never an owner. System entries reference recipe paths; recipes live in their Calibration / Errors subsystem catalogues. |
| Plugin contribution path | Plugins extend Layer 1 and Layer 2 only. They do **not** register `command.*` entries except in the rare custom-comms exception (`command.do.<plugin>.*`). |
| Universal bus scope (v1) | `command.fleet.*` only. `command.mc.*`, `command.plugin.*` are deferred. |
| Live-mission gate | Recipes declare a risk tier; the runner enforces it via the existing live-mission gate primitive — no new gate machinery. |

### Layer 0 conventions

- **Name shape:** `command.<addressing-path>.<verb>.<specifier-path>` (e.g. `command.fleet.vehicle.do.calibrate.compass`).
- **Lexical rules:** lowercase ASCII letters, digits, dots; bounded length 128.
- **Response taxonomy:** every stack converter must classify every raw outcome into the closed `FleetCommandErrorKind` set — recipes branch reliably on `error.<kind>` without parsing free-form strings.
- **Descriptor metadata:** declared response kinds, retry hints (read by Layer 1 only — Layer 0 itself is single-shot), risk tier, optional `containsCommands` for composites.

### Layer 1 conventions

- **Name shape:** `recipe.<subsystem>.<specifier-path>` (e.g. `recipe.fleet.calibrate.compass`); same lexical rules as commands; no verb segment.
- **Catalogue retry default** (used when neither a step nor a recipe declares its own): `1 retry × 250 ms fixed delay × { timeout, .noSession, .autopilotBusy }`. Authority and validation failures **never** retry by default.
- **Retry caps** (parser hard-fails on violations): `maxAttempts ≤ 5`, `delaySeconds ≤ 5s`, worst-case additional time ≤ 15s. A descriptor may opt out with `relaxRetryCaps: true` — the registry then logs-and-warns instead of rejecting.
- **Payload predicate vocabulary** (closed 8-kind set): `keyValueEquals`, `keyValuePresent`, `boolEquals`, `stringEquals`, `stringMatches(regex)`, `integerCompare(op, value)`, `doubleCompare(op, value)`, `stringListContains`. Regex patterns are compiled at parse time.
- **Escalation reason** (closed top-level): `operatorActionRequired(kind) | unrecoverableFailure(kind) | confirmation(kind)`. The kinds themselves are string-backed extensible namespaces (`Notification.Name`-style) — plugins can declare new kinds without core changes.
- **Resumption verbs** (closed set): `acknowledge | retry | skip | abort`. A matcher's `allowedVerbs` filters which verbs the runner accepts when resuming.
- **Recipe body budget:** `60s` default, hard cap `600s`.
- **Parser-time validation** (single pass, every error surfaced): step-ID uniqueness; entry-step exists; matcher lists non-empty; `.any` matcher only in final position and never duplicated; `.branch(stepID:)` targets exist in the same body; invoked commands and recipes are registered; **1-level recipe-composition depth**; regex predicates compile; overall budget positive and within cap; per-step retry policy within caps unless the descriptor opts out.

### Layer 1 runner

`FleetRecipeRunner.shared` is the `@MainActor` singleton that drives a registered recipe body end-to-end. It is the single execution surface for Stage E's wizard, future Stage D operator-prompt routing, and any subsystem-level autonomous flow (e.g. Paladin's headless calibration). Source: `Sources/GuardianHQ/Systems/Fleet/Subsystems/RecipesCatalogue/FleetRecipeRunner.swift`.

- **Public surface:** `run(recipe:parameters:vehicleID:source:fleetLink:escalationHandler:) async -> FleetRecipeOutcome` and `cancel(vehicleID:) -> Bool`. The runner does not own a `FleetLinkService` — callers pass it through `run(...)` and the runner forwards it to `FleetCommandsCatalogue.invoke(...)` for dispatch.
- **Concurrency model:** **one active run per vehicle, refuse-on-conflict.** A second `run(...)` targeting a vehicle that already has an active run returns `.failed(detail: "… already executing recipe …")` immediately. Callers handle retry/queueing. `invokeRecipe` step expansions bypass this gate because they're part of the parent run's accounting.
- **Outcome shape:** binary `FleetRecipeOutcome.succeeded(detail, payload, trace)` / `.failed(failingCommandPath, lastResponse, detail, trace)`. Cancelled and budget-breach scenarios are reported as `.failed` variants with attribution in `detail` (`"cancelled"`, `"recipe budget exceeded (60s)"`, etc.).
- **Step machine:** matchers are evaluated top-to-bottom against the dispatched step's response; the first match wins and produces a `FleetRecipeControlOutcome`. `.continueToNextStep` advances by index; `.branch(stepID:)` jumps to a sibling step; `.retry` re-invokes the same step (bounded only by the recipe's overall budget); `.succeed` / `.fail(detail)` terminate the run; `.escalate(reason, allowedVerbs)` suspends until the escalation handler returns a resumption verb.
- **Retry policy:** auto-retries inside a single dispatch consume the step-level (or descriptor-level) `FleetRecipeRetryPolicy`. The catalogue's locked default (`1 retry × 250 ms × {timeout, .noSession, .autopilotBusy}`) applies when neither is specified. Explicit `.retry` control outcomes are authoring-driven and intentionally **not** counted against `maxAttempts` — they're bounded by `FleetRecipeBody.overallBudgetSeconds`.
- **Cancellation:** `cancel(vehicleID:)` sets a flag on the active run. The in-flight Layer 0 command runs to completion (Layer 0 does not expose mid-flight cancel in v1), then the runner returns `.failed(detail: "cancelled")`. If the descriptor declares `FleetRecipeDescriptor.cancelRecipe`, that recipe is dispatched with empty parameters as cleanup **before** the parent outcome is returned. Cancel during cleanup is a no-op.
- **Live-mission gate:** consulted **only at top-level `run(...)` entry** (not at `invokeRecipe` child boundaries — the parent recipe's tier is authoritative). Wiring: `FleetRecipeRunner.shared.liveMissionGate` is a `(vehicleID) -> Bool` closure installed once at app start by `RootView.onAppear` against `MissionControlStore.isVehicleStreamUsedInLiveMission(...)`. When the gate fires and `allowDuringLiveMission == false`: `.groundOnly` recipes refuse with `"… is groundOnly; vehicle … is in a live mission. Pass allowDuringLiveMission=true to override."`; `.confirmInLiveMission` recipes refuse with `"… requires operator confirmation …"`; `.safeInLiveMission` recipes ignore the gate. Callers (Stage E wizard, MCR reserve-deploy / get-back-online flows) collect operator confirmation themselves and re-invoke with `allowDuringLiveMission: true`. A `nil` gate disables enforcement (tests, surfaces without a Mission Control store).
- **`cancelRecipe` field on the descriptor:** optional `FleetRecipeName?`. The catalogue rejects the parent registration if the cleanup recipe is unregistered, has its own `cancelRecipe`, or is composite (`containsRecipes` non-empty). v1 supports **one cleanup recipe per parent**; per-step cleanup hooks are a Stage B2 follow-up.
- **Escalation handler:** `FleetRecipeEscalationHandler` is `@MainActor (FleetRecipeEscalationEvent) async -> FleetRecipeResumptionVerb`. Callers pass a handler to `run(...)`; absent that, the runner uses `FleetRecipeRunner.shared.defaultEscalationHandler` (defaults to `.abort`, replaced by Stage D's router at app start). The runner **rejects** any verb that is not a member of the escalating matcher's `allowedVerbs` list (the run fails with attribution).
- **Audit trace:** `FleetRecipeAuditTrace` attaches to every outcome. One entry per dispatched step (retries within a single dispatch collapse into the entry's `attempt` count; explicit `.retry` outcomes produce additional entries because they re-enter the step). Each entry carries the step ID, the kind (`command` / `recipe`), attempt count, response, control outcome, and timestamp. The trace is **flat** — child-recipe expansions produce a single parent entry rather than a nested trace.
- **Body-less descriptors are refused at entry.** Stage C registers descriptors and bodies in independent passes; the runner short-circuits a body-less recipe with `.failed(detail: "… has no body …")` rather than silently succeeding on an empty step list.

### Extension points

- **New core command** → add to `FleetVehicleCoreCommandRegistrations.registerAll()` plus stack-converter coverage (or a documented `.notImplemented`).
- **New subsystem recipes** → add the recipe to its subsystem's `registerAll()` entry point (e.g. `FleetCalibrationRecipeRegistrations.registerAll()`). The bootstrap already invokes calibration and errors entry points; new subsystems get a sibling directory under `Subsystems/`, a JSON catalogue resource (declared in `Package.swift`), a `@MainActor` entry-point enum, and one extra `registerAll()` call inside `FleetRecipesCatalogueBootstrap.ensureRegistered()`.
- **Plugin contributions** → register through `GuardianPluginBootstrap` once Stage F manifest namespace claims land; until then, plugins can register directly but should claim their namespace (`plugin.<id>`) in `FleetRecipeDescriptor.pluginID` for discoverability.

### Standing rule

Do **not** treat a registered descriptor as "done" unless the stack converter either performs a real, verifiable action **or** returns a deliberate, documented `.notImplemented` because the required transport is genuinely unavailable. The same rule applies to recipe bodies — a registered body that no step can actually run is worse than no body at all.

## Adding another autopilot “stack” later

Rough checklist so fleet badges, sim picker, and MAVLink stay consistent:

1. **`FleetAutopilotStack`** (`Sources/GuardianHQ/FleetAutopilotStack.swift`) — add a `case`, `displayName`, and `badgeBackground` for the new stack.
2. **`SimulationPlatform`** (`Sources/GuardianHQ/SimulationCatalog.swift`) — add a case if Guardian will **spawn** that stack from the app; wire the picker and `SitlService`.
3. **Live vehicle detection** — extend `mavsdk_bridge.py`: after `connect()`, map vendor/product (or MAV enums) to the same **lowercase** string you use as `FleetAutopilotStack.rawValue`, and emit `{"type":"vehicle_stack","stack":"<raw>"}`. Handle it in `FleetLinkService.handleBridgeStdoutLine` (already decodes `vehicle_stack`).
4. **SITL launch** — implement a recipe in `SitlLaunchRecipe.swift` / `SitlService.swift` (see ArduPilot and PX4 paths).

Keep `vehicle_stack` JSON values aligned with `FleetAutopilotStack` `rawValue` strings (`ardupilot`, `px4`, `unknown`, plus any new cases).

## Child processes and cold launch (orphan cleanup)

After a **force quit**, macOS can leave Guardian-spawned subprocesses running. On each **cold app launch**, `GuardianSitlOrphanBlitz` tears down known orphans: persisted root PIDs from `GuardianSitlSpawnRegistry`, ArduPilot/PX4-oriented `pgrep` patterns derived from `SitlLaunchRecipe`, and the **whole process tree** under each matched root (so helpers like MAVProxy or `px4-mavlink` go away with the parent).

**If you add new spawn methods or long-lived services**—including anything **outside** ArduPilot/PX4—you need to keep that behavior correct:

1. Prefer spawning through **`SitlProcessRunner`** (or the same registration hook it uses) so the root PID is recorded in **`GuardianSitlSpawnRegistry`** after `Process.run()` succeeds, and unregistered when the process exits cleanly.
2. If the new stack cannot use `SitlProcessRunner`, you must still **register** the root PID (same registry API) and ensure **`GuardianSitlOrphanBlitz`** can find it again after a crash—typically by adding **narrow, path-specific** `pgrep` patterns (see existing ArduPilot/PX4 patterns) so unrelated user processes are never matched.
3. For local debugging only, `GUARDIAN_SKIP_SITL_ORPHAN_BLITZ=1` disables the startup blitz.

Skipping the above leaves orphans after force quit and breaks the expectation that Guardian cleans up everything it started.

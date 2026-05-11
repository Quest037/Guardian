# Commands & Recipes — Layered Architecture To-Do

Forward-looking tracker for the Fleet **Commands → Recipes → Processes** architecture.
Companion to `TODO.md`.

Locked layer model, layout, conventions, retry/parser/depth rules, and extension
points live in `README.md` (**Fleet Commands & Recipes architecture**). This
file tracks **what is still in flight for the product-facing next phase**.

---

## Shipped (reference)

Layers **0–1** (fleet command catalogue, stack converters + taxonomy, recipe
catalogue + JSON bodies, **FleetRecipeRunner**, live-mission gate, cancelRecipe
cleanup, plugin manifest claims), **Stage D primitives** (`OperatorPromptEvent`,
`OperatorPromptRouter`, `OperatorPromptResumptionChannel`, policies), **Stage G**
deterministic tests + opt-in SITL (`GuardianHQSitlSmokeTests`) and
**RecipeEscalationOperatorPromptIntegrationTests** — all live in tree + README
Stage G table. No checklist here; git history + README are the audit trail.

---

## Next — Stage E: Vehicle Inspector recipe wizard

**Goal:** Replace hardcoded calibration / preflight entry points with a
**directory-driven** flow that runs **recipes**, shows **progress**, and resolves
**escalations** inline (using the same vocabulary as Mission Control / LiveDrive
later).

- [ ] **OperatorPromptCenter** — stateful host: registration, dispatch + mirror
  withdrawal, per-event expiry, `publish(_:) async -> OperatorPromptAnswer`
  (or equivalent) built on `OperatorPromptResumptionChannel` +
  `OperatorPromptRouter` (today callers use the channel + router directly).
- [ ] **Wizard shell** — single Vehicle Inspector surface: recipe picker /
  progress / step transcript / escalation affordances wired to
  `FleetRecipeRunner` + `wizardProgressByVehicleID` /
  `vehicleInspectorWizardEscalationHandler(for:)`.
- [ ] **Calibration tab** — Run rows already honour live-mission gate; wire
  **Start** into real wizard runs (not one-off command buttons where a recipe
  exists).
- [ ] **Preflight / arm-help** — surface `recipe.fleet.diagnose.armprobe` and
  `recipe.fleet.errors.fix.calibrationrequired` (and siblings) where the product
  currently hardcodes arm / calibration copy.

---

## Next — MRE recipe executor

**Goal:** `MissionRunEnvironment` execution stops building bespoke
`FleetVehicleCommand` trees and instead drives **named recipes / catalogue
commands**, with outcomes in the **FleetCommandResponse** taxonomy and operator
prompts as **recipe escalations** (not ad-hoc bottom prompts).

- [ ] **Subsystem forward-port** — `MissionRunCommandSubsystem` (and related call
  sites) invoke `FleetCommandsCatalogue` / `FleetRecipeRunner` instead of
  `FleetLinkService.executeVehicleCommand` + hand-rolled `FleetVehicleCommand`
  cases (arm, goto, upload, RTL, …).
- [ ] **Upload + arm + start** — replace implicit
  `runUploadArmStartMissionPipeline` / `FleetVehicleCommand.uploadAndStartMission`
  with a **catalogue-level** composite (`do.mission.upload.start` or equivalent
  **recipe**) so the behaviour lives in one place.
- [ ] **Retire** `FleetVehicleCommand.uploadAndStartMission` once all MRE paths
  go through recipes/commands above.
- [ ] **Prompts** — MRE operator prompts become escalation / prompt-channel
  events (same path as Vehicle Inspector wizard), not parallel
  `GuardianBottomPromptCenter` one-offs.

---

## Open design questions (next phase)

- **Prompt router placement:** App layer (alongside `withToasts`, `withAppDrawer`)
  vs Fleet subsystem? Likely **App** so LiveDrive + MCR share one host.
- **Wizard chrome:** keep inside Vehicle Inspector modal vs extract reusable
  `RecipeWizardOverlay` for MCR / LiveDrive.
- **Stage F plugins:** namespace claims **fail-closed** on publish vs
  warn-then-skip on invoke — decide when plugin-owned recipes ship in product UI.

---

## Cross-references (`TODO.md` absorbs / defers here)

- `## Vehicles System → Vehicle Calibration → Manual Calibration Process` →
  **Stage E** above.
- `## Vehicles System → Vehicle Preflight → Attempt to arm…` → recipes exist;
  **Stage E** + MRE executor for product wiring.
- `## Mission Control → MissionRunEnvironment → Executor` → **MRE recipe
  executor** above (single canonical backlog).
- `### Commands Catalogue` / stack work → README + `CommandsCatalogueDoc.md`;
  remaining **mission** atoms stay under `TODO.md` → **FleetCommands**.

---

## Revisit — operator messaging (notifications / toasts / inline recipe copy)

- [ ] **Unify and split responsibilities** for operator-facing text across
  procedure-failure banners, toasts, and inline remediation on system cards so we
  do not duplicate the same headline + bullet list in multiple places at once.
  Needs a clearer model: which surface owns the headline, which owns
  stack-specific explanation, which owns next-step CTAs, and how catalogue /
  mapper / advisor contribute without echo.

## Status legend

- `[ ]` not started
- `[x]` completed
- `[~]` in progress (use sparingly; prefer breaking into smaller items)
- `[!]` blocked — note blocker inline

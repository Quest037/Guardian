# Task / roster assignment / vehicle state — MRE tracking & auto-triage

Operator goal: **Mission Run Environment (MRE)** should know when each **task**, each **roster slot (assignment)**, and each **bound vehicle** has reached meaningful lifecycle milestones—especially after **abort** or **complete** policies—so the UI can **auto-mark** task triage (`aborted` / `completed`) when evidence is satisfied, without manual “mark task done” steps. **Fleet vehicle state** stays **operational** (link, arm, health, reserve eligibility); it must not duplicate mission outcome semantics.

This file is the **step-by-step backlog**. Completed work should be removed per repo todo hygiene (migrate durable decisions to `README.md` first).

---

## 0 — Locked vocabulary (three layers)

| Layer | Meaning | Examples today / target |
|-------|---------|-------------------------|
| **Task state** | Operator + MRE view of a **mission task** within a run | `MissionTaskState` (`MissionControlModels.swift`) — derived + operator triage pin |
| **Roster slot state** | Per-**assignment** (`MissionRunAssignment`) progress for that task’s row in the roster | ``MissionRunAssignmentSlotState`` + optional ``slotLifecycleLanes`` (Codable); MRE **writers** + hub rollup still **TaskRosterAssignmentStatesToDo.md** §3–§4 |
| **Vehicle state** | **Fleet** functional readiness (live, sim, written-off, battery gates, etc.) | `VehicleLifecycleStatus`, reserve draw/return rules, `writtenOffFleetVehicleStorageKeysForReservePool` on `MissionRunEnvironment` |

**Rule:** Slot state answers “did **this slot’s** abort/complete/recipe/mission leg finish?” Vehicle state answers “is **this airframe** still usable / swappable?”

### Task state — **attempting** vs **current** (dual aspect)

Today `MissionTaskState` largely reads as a **single** lane (`deriveMissionTaskState` + operator triage pin). Add an explicit **two-track** (or paired-field) model at **task** scope so MRE, Paladin, and the operator can tell:

| Aspect | Meaning | Example |
|--------|---------|--------|
| **Current** | Settled, authoritative label for UI + rollup gates | `executing`, `ready`, operator-pinned `aborted` / `completed`, or derived terminal once all evidence is in |
| **Attempting** | In-flight **intent** the system is driving toward | `attemptingAbort` — abort policy / wind-down **issued** but not all roster slots have satisfied evidence yet; Paladin can bias prompts and nudges **toward** that outcome without claiming the task is already triage-`aborted` |

**Why:** If `current` already flips to “aborting” only when session phase says so, operators still need a crisp “we are **working** on abort” signal that is distinct from “abort is **done**.” Same pattern for complete/recovery (`attemptingComplete` / `attemptingRecovery`) if product copy needs it.

**Implementation sketch (pick one in design):** (a) optional `MissionTaskAttemptState?` (or non-optional with `.none`) alongside derived `MissionTaskState`; (b) nested struct `MissionTaskLifecycleSnapshot { current: MissionTaskState; attempting: … }` published per task ID; (c) widen `MissionTaskState` enum — usually worse for pattern-matching. Slot-level states remain the **evidence** that clears **attempting**.

---

## 1 — Inventory (what exists now)

Full **MissionRunStatus** × **MissionRunSessionPhase** × **MissionTaskState** reference (and operator-action summary) lives in **README.md** → **Mission run state model (run vs per-task)**. **Task attempting vs current** (`MissionTaskAttemptState`, ``MissionRunEnvironment/taskAttemptingByTaskID``) → same section → **Task attempting vs current (`MissionTaskAttemptState`)**. **Task derivation inventory** (inputs, who refreshes, who mutates ack / triage sets) lives in the same section → **Task derivation — inputs, refresh triggers, ack-set writers**. **Per-task wind-down flags** (pending after-cycle map, abort/complete **issued** sets, autostart suppression pairing, clears vs revoke) → **Task-scoped wind-down flags (pending map + issued sets)**. **Session phase lifecycle** (enum meanings, every ``setSessionPhase`` caller, ``aborting`` → ``aborted`` promotion vs ``markFailed``, disabled-task cardinality for promotion) → **MissionRunSessionPhase (enum + transitions + abort promotion)**. **Roster row model** (``MissionRunAssignment`` / ``MissionRunAssignmentPolicies``, resolution, ``assignmentsBoundToMissionTask``, Codable, optional ``slotLifecycleLanes`` + ``effectiveSlotLifecycleLanes``) → **MissionRunAssignment (roster row model)** + **Roster slot state storage (design tradeoffs)** (option **(a)** on-row **locked** in README; provisional ``MissionRunAssignmentSlotState`` + **commanded vs observed lanes** / ``MissionRunAssignmentSlotLaneMerge`` in `MissionControlModels.swift`; MRE writers for lanes **not** wired). **Floating reserve pool** (binding-only pool slots vs mission policy lifecycle; reconcile with §2 slot state) → **Floating reserve pool (Mission Control run)** — intro + **Mission / slot policy state (inventory)** paragraph. **Fleet-side evidence** (issued commands, run logs, recipe/catalogue outcomes, hub, FVM command ring vs `recipeRunHistory`) → **Fleet evidence sources (Mission Control inventory)**. **Task-scoped abort/complete dispatch** (environment → scheduling → executor, per-assignment commands, exit paths, fleet follow-on) → **Task-scoped abort / complete dispatch (entry + exit paths)**.

---

## 2 — Design phase A — Roster slot state model

**Task attempting (v1) is shipped:** derived ``taskAttemptingByTaskID`` + ``MissionTaskAttemptState`` (README **Task attempting vs current**). **Slot lanes on assignment (Codable, on-row / option (a)):** optional ``MissionRunAssignment/slotLifecycleLanes`` + ``effectiveSlotLifecycleLanes`` — README **MissionRunAssignment** + **Roster slot state storage**; **v1** ``MissionRunAssignmentSlotState/displayTitle`` UX lock in `MissionControlModels.swift` + tests; **v1** MC-R/MCS roster slot chip contract (README **Roster slot state storage** → MC-R roster slot chip) in `MissionControlRosterSlotCard`, ``MissionLiveVehicleHealthCard``, task list; writers still TBD (§4). Per-**slot** runtime container + evidence paths remain below.

---

## 3 — Design phase B — Evidence & auto triage

- [ ] **Success criteria catalogue** — per **abort policy** / **complete policy** / recipe (RTL, loiter, move+park, arm-probe, …): define **required evidence** (recipe terminal success, hub: mode + disarmed + distance to rally, mission cleared, etc.) and **timeouts**.
- [ ] **Push path** — subscribe to `FleetRecipeRunner` / catalogue completion for the **exact** run+assignment correlation (source tags, `MissionRunIssuedCommand` metadata); map to slot `policySucceeded` / `policyFailed`.
- [ ] **Pull path** — periodic MRE **conformance check** (hub + mission state) when push incomplete or stacks without rich callbacks; debounce + GPS tolerances.
- [ ] **Failure classes** — which `policyFailed` still **rollup to “task resolved”** for auto-triage vs leave task in `aborting`/`recovery` with operator prompt.
- [ ] **Auto `operatorMarkMissionTaskTriageState` equivalent** — new internal API: when **all** assignments for task `T` are in terminal bucket, insert `T` into `taskMissionEndAbortCompletedByTaskID` or `taskMissionEndRecoveryCompletedByTaskID` **without** requiring manual triage; emit log + toast.
- [ ] **Partial fleets** — task with 3 slots: 2 succeeded, 1 `blockedNoVehicle`: define whether task can auto-complete or stays blocked.
- [ ] **Idempotency** — repeated telemetry ticks must not double-insert or thrash session phase.

---

## 4 — Implementation phase C — Core runtime

- [ ] **Slot-evidence-driven attempting** — ``MissionRunEnvironment/taskAttemptingByTaskID`` exists (README **Task attempting vs current**); today it clears from orchestration flags + triage only. Re-derive (or clear early) from per-slot terminal evidence when §3 lands, without forking ``MissionTaskState`` until rollup rules say so.
- [ ] Add slot state container + mutation API on `MissionRunEnvironment` (or assignment model) with **single writer** discipline (main actor / subsystem).
- [ ] Wire **dispatch start**: when fleet commands/recipes leave MRE for an `assignmentID`, transition slot from `idle`/`staging` → `executing…` / `policyAborting` / `policyCompleting` as appropriate.
- [ ] Wire **dispatch outcome** handlers (success / error / timeout / escalation resolved → retry or terminal).
- [ ] Integrate **recipe run IDs** / `FleetRecipeOutcome` trace if needed to disambiguate concurrent recipes on same vehicle.
- [ ] Update `deriveMissionTaskState` (or successor) so **`aborting` → `aborted`** and **`recovery` → `completed`** can flip from **slot rollup** in addition to operator triage.
- [ ] Revisit `promoteSessionPhaseToAbortedIfAllTasksAcknowledgedAbort()` — extend condition from task sets to **assignment-level** completion where required.
- [ ] **Tests** — pure rules: rollup function (given slot states → task terminal?), Codable round-trip for new fields, regression: manual triage still overrides when operator insists.

---

## 5 — Implementation phase D — Reserve pool & vehicle interplay

- [ ] **Reserve draw / return** (README floating reserve + this file’s slot-state model): when a vehicle is swapped, define whether old slot row gets `supersededReassigned` and how new binding inherits state (`idle` vs inherit `executingMission`).
- [ ] **`qualifiesForMissionRunReservePoolOperationalDraw`** — ensure slot `policyFailed` / `blockedNoVehicle` does not deadlock reserve logic.
- [ ] **Written-off vehicles** — slot state `blockedNoVehicle` vs fleet written-off set: single operator-facing explanation.
- [ ] **SITL vs live** — same state machine; feature-flag only if hardware timing differs.

---

## 6 — Implementation phase E — Operator surfaces

- [ ] Task header / chip: show **attempting** line when non-nil (e.g. “Abort in progress”) even if `MissionTaskState` still reads `aborting` vs `aborted`; avoid duplicating confusing labels — copy pass with operator review.
- [ ] **MC-R / MCS roster slot chip polish** — richer tooltips than v1 title-as-help, empty-slot cues, triage / map density (base chip + severity shipped in §2 README contract).
- [ ] Triage sheet: show **which slots** block auto-complete; offer **manual triage** override (existing behaviour preserved).
- [ ] Notifications: when auto-triage fires, single consolidated line in run log + optional toast.
- [ ] **Theme** — use `GuardianTheme` / semantic colours for blocked vs succeeded (see `.cursor/rules/guardian-theme-tokens.mdc`).

---

## 7 — Documentation & cleanup

- [ ] **README** — short “Mission run state model” section: task vs slot vs vehicle; pointer to this file until backlog empty.
- [ ] **AGENTS.md** or Mission Control subsystem doc — one paragraph for agents editing MRE dispatch.
- [ ] When this backlog is fully delivered: **delete this file** after migrating any standing rules to `README.md` (todo hygiene).

---

## 8 — Open decisions (resolve before coding enums)

1. **Naming** — `attempting` vs `intent` vs `pendingWindDown`; pair names for **current** (`settled` / `display` / unchanged `MissionTaskState`).
2. **Granularity** — One attempting flag per task vs per **kind** (`attemptingAbort` | `attemptingComplete` mutex?) so overlapping signals cannot collide.
3. **Recovery exposure** — Do we expose “Recovery” at slot level or only at task level (today task uses it for complete wind-down)?
4. **Empty roster rows** — `notApplicableEmptySlot` vs omit from rollup denominator?
5. **Graceful after-cycle** — slot stays `executingMission` until cycle boundary, then `policyAborting`: single state or sub-state machine?
6. **Authority** — Can Paladin/plugin ever advance slot state, or only MRE + fleet evidence?

---

## Key file references (for implementers)

- `Sources/GuardianHQ/Systems/MissionControl/Models/MissionControlModels.swift` — `MissionTaskState`, `MissionRunStatus`, `MissionRunSessionPhase`, `MissionRunAssignment` (+ optional `slotLifecycleLanes`), `MissionRunAssignmentSlotState` / lanes / merge, policies
- `Sources/GuardianHQ/Systems/MissionControl/Services/MissionRun/MissionRunEnvironment.swift` — derived task state, triage sets, reserve pool, written-off keys
- `Sources/GuardianHQ/Systems/MissionControl/Services/MissionRun/MissionRunExecutionSubsystem.swift` — abort/complete immediate + graceful delivery
- `Sources/GuardianHQ/Systems/MissionControl/Services/MissionRun/MissionRunCommandSubsystem.swift` — catalogue/recipe dispatch, summaries
- `Sources/GuardianHQ/Systems/MissionControl/Models/MissionRunReservePool.swift` — floating reserve slots
- **README.md** — **Floating reserve pool (Mission Control run)** (shipped mechanics + tests); **NEXTVERSION.md** — **Floating reserve pool — deferred phases** (2026-05-12) for auto triggers / executor / audit / optional MC-R edits.
- **`MissionRosterReservesToDo.md`** — **live reserve swap-in** pipeline (active ↔ reserve / pool): phases, UI, triggers, class matching (not started).

---

## 9 — Full task lifecycle upgrade (cross-cutting)

Stretch goal: MRE + MC-R reflect the **entire** task journey—not only abort/complete wind-down and derived ``MissionTaskState``—including **cycle start intent** (e.g. ``operatorTriggered`` **Trigger**), planner / dispatch **failure** vs in-flight mission upload, **between-cycle** semantics, and convergence with **slot** + **vehicle** layers so auto-triage and Paladin share one truth.

- [ ] **Confirm scope with operator (blocking)** — Before large enum or UI expansions, agree in writing (thread or doc) what “full lifecycle” **must** include vs **defer**: e.g. operator-triggered start **attempting** / **failed** vs log-only; whether ``MissionTaskAttemptState`` grows vs a separate ``MissionTaskStartOutcome``-style model; timeout / retry semantics; relationship to ``TaskRosterAssignmentStatesToDo.md`` §3 evidence catalogue and ``MissionRosterReservesToDo.md`` swap-in phases. **Do not** treat this bullet as complete until that confirmation exists.
- [ ] **Implement agreed lifecycle model** — wire ``MissionRunEnvironment`` / executor / command paths + ``refreshDerivedTaskStates`` (or successors) + tests per confirmation above; align README **Mission run state model** and remove redundant bullets here via todo hygiene.
- [ ] **Operator surfaces** — MC-R / triage / chips reflect the new states without “future version” copy; theme tokens per `.cursor/rules/guardian-theme-tokens.mdc`.

# MRE squads — conversion checklist

Squad = **primary roster row** per task path (AUTO mission cycles on primary only). Wingmen/reserves: **OFFBOARD / GUIDED + FOLLOW** later — **ignored** for MAVLink mission-cycle boundaries.

**Stagger:** always on structurally; **`MissionTask.executionMethod` (group vs staggered) removed** from MV + MCS. Stagger **trigger** is configurable (fixed seconds, waypoint hit, operator first-wave gate, then per-squad loops).

**Squad naming:** sequential under task, e.g. task **Dagger** → **Dagger:1**, **Dagger:2**, …

**Operator:** **squad-level complete / abort** required in addition to existing **task-level** complete/abort.

---

## Auto pipeline — task recovery → complete (locked)

Whole-run / task auto wind-down chooses **recovery → complete** unless **every** squad is in or headed to **aborting / aborted** (squads already aborting/aborted are **disregarded** when deciding that branch among the rest).

| Squads | Situation | Task auto pipeline |
|--------|-----------|-------------------|
| 3 | 1 aborting/aborted; 2 grace-complete; 3 complete-now | **Recovery → complete** |
| 2 | 1 completed; 1 executing → abort now | **Recovery → complete** |

**Rule:** Auto **recovery → complete** unless **all** squads are aborting/aborted (or going there). Mixed abort + complete squads still yields **recovery → complete** per table above.

---

## Cross-task / cross-squad independence — scheduling & state (product lock)

**Product lock:** Mission tasks (and, under this doc, **each primary squad** as its own cycle owner) are **independent execution threads** while the run is live. **No path may stall, re-derive, or finalize another path’s cycles** except where the product explicitly shares a dependency (e.g. **whole-run** operator stop, or **one physical vehicle** / one serialized fleet barrier—those exceptions must be **listed and scoped**, not “any task in end mode freezes the mission”).

**What went wrong (current coupling — do not preserve):**

1. **`MissionRunExecutionSubsystem.processMissionCycleFinished`** wraps `planNextAutoCycleStarts(...)` in `if !environment.shouldSuppressBetweenCycleAutostartForMissionEndWindDown()`. When that boolean is true, **no task** gets the next-cycle plan—even though **`unionedMissionTaskIDsSuppressingAutopilotAutostart(forMission:)`** already carries a **per-task** suppress set.
2. **`MissionRunEnvironment.shouldSuppressBetweenCycleAutostartForMissionEndWindDown()`** returns true if **any** of: `gracefulStopKind != .none`, **any** pending per-task graceful row, **any** task in `missionTaskCompleteWindDownIssuedTaskIDs` / `missionTaskAbortWindDownIssuedTaskIDs`. The **per-task** arms must **not** imply mission-wide “nobody autostarts.”
3. **`deriveMissionTaskState`** (same file) maps both `.continuous` and `.continuousWithDelay` to **`.between`** whenever `cyclesDone > 0` and the task is not in `activeCycleTaskIDs`. That is “off-cycle gap,” not “this task has a delay policy.” If autostart is frozen globally because of (1–2), a **pure continuous** path can sit in **`.between`** indefinitely even though product-wise it has “no between”—**misleading UI caused by cross-task coupling**, not operator intent.
4. **Run-level** `status == .recovery` / `sessionPhase == .recovery` still forces **every** task through recovery derivation until acked; that is correct **only** when the operator or system truly ended the **whole run**. Per-path end must **not** promote whole-run recovery (separate from squad work; keep regression tests when touching `completeRun` / finalize paths).

**Concrete work (check off as done; avoid vague refactors):**

- [ ] **Split the autostart gate:** Always allow `planNextAutoCycleStarts` to run after cycle processing **unless** the freeze is **whole-run** (`gracefulStopKind != .none` or a deliberately documented global SIM/fleet barrier). For per-task / per-squad end, pass **`suppressAutostartForTaskIDs`** from `unionedMissionTaskIDsSuppressingAutopilotAutostart` (and extend that set if new “ending” markers appear) so **only** ending paths skip autostart—not siblings.
- [ ] **Deprecate or narrow** `shouldSuppressBetweenCycleAutostartForMissionEndWindDown()`: either remove its use as a mission-wide guard, or redefine it to **whole-run only** and rename so callers cannot OR in per-task flags again. Any remaining “block everyone” must cite **fleet queue / single-vehicle** invariant in a comment next to the guard.
- [ ] **Re-audit** `processMissionCycleFinished` branches that use `activeCycleTaskIDs.isEmpty` + suppression + `missionHasOnlyBoundedTasks` / `finalizeWholeRunGracefulAfterLastAutopilotCycle`: empty active set must **never** mean “finalize whole run” without **whole-run** operator intent (see prior fix using `gracefulStopKind`; extend tests for two unbounded paths + one path ending).
- [ ] **`deriveMissionTaskState` / UI copy:** Once autostart is per-path, re-evaluate whether `.between` for delay-less `.continuous` should remain or be renamed / split (e.g. “next cycle pending” vs “between-cycles tactic”). Prefer aligning with **§3 squad-level** “between” so the task card stays **rollup-only** and does not fake a between state another path caused.
- [ ] **Squads (same lock):** When §3–4 introduce per-squad cycle keys, apply the same rule: **one squad’s** end or recovery must not cancel `planNextAutoCycleStarts` for **another squad’s** primary on a **different** vehicle. Shared suppression only when **same resolved stream id** or explicit recipe barrier—document in planner/executor.
- [ ] **Tests to add before closing this section:** (a) Task A `continuousWithDelay` in issued complete wind-down; Task B pure `continuous` with separate primary—B must re-enter active cycle / executing without operator restart. (b) Two squads same task, staggered: squad 1 ending must not freeze squad 2’s cycle loop on a different primary. (c) Whole-run `completeAfterCycle` (`gracefulStopKind`) still freezes all paths until finalize—**only** scenario where “everyone stops together” is intended.

**Do not:** widen `shouldSuppressBetweenCycleAutostartForMissionEndWindDown` to more OR conditions; use `activeCycleTaskIDs.isEmpty` alone as “no work left” for mission scope; or add new global flags that mirror per-task state without a named whole-run / shared-vehicle reason.

---

## 1 — Mission & template models (`Mission`, `MissionTask`)

- [ ] Remove `MissionTaskExecutionMethod` / group vs staggered from model, Codable, UI, docs.
- [ ] Add **stagger trigger** model on task (fixed delay seconds, waypoint-index trigger, operator first-cycle gate — exact fields TBD).
- [ ] Document **per-squad cycle cap** = task `cycles` value × each primary squad (N squads × each does full count).
- [ ] Template / JSON: migration or one-shape decode policy (align with repo **no legacy** rules).
- [ ] Mission workspace copy: primaries define squads; stagger trigger; no “group” wording.

---

## 2 — Planner (`MissionRunPlannerSubsystem`, geofence resolution)

- [ ] Keep `buildTaskSquadMissions` / `PlannedTaskSquadMission` as squad list source; ensure ordering matches roster template **Dagger:1…**.
- [ ] Any plan compile logs / `taskTopology` / `teamTopology` strings still truthful after execution-method removal.
- [ ] Geofence squad lists unchanged in intent; verify per-squad mission items still build when only primary cycles.

---

## 3 — Mission run environment (state, derivation, persistence)

- [ ] Introduce **squad lifecycle state** (executing, between, recovery, completed, aborting, aborted, … — align enum with product list).
- [ ] **Per-squad** cycle counters (and/or finished flags) keyed by stable id (`assignment.id` or `(taskID, squadIndex)`).
- [ ] Replace or extend `activeCycleTaskIDs` + `finishedMissionCycleVehicleIDsByTaskID` with **per-squad** in-flight / finished tracking for primaries.
- [ ] **`deriveMissionTaskState`:** after task start → **`executing`** until task-level recovery/aborting from **rollup**; remove task **between** (moved to squads).
- [ ] **Rollup rules:** all squads `.recovery` ⇒ task `.recovery`; all squads aborting/aborted ⇒ task abort path; **auto recovery→complete** unless every squad aborting/aborted per locked table.
- [ ] `taskCyclesCompletedByTaskID` / run `cyclesCompleted` / reporting: **per-squad + task aggregate** per product.
- [ ] `refreshDerivedTaskStates` triggers + any new `@Published` squad maps wired through `MissionControlStore` / `updateRun`.

---

## 4 — MRE execution (`MissionRunExecutionSubsystem`, command queue)

- [ ] **Cross-task / cross-squad independence (scheduling gate):** implement **Cross-task / cross-squad independence** section above **before** or **together with** per-squad cycle work so `planNextAutoCycleStarts` is never skipped for path B solely because path A has per-task mission-end markers (`gracefulStopKind` vs per-task sets).
- [ ] **`processMissionCycleFinished`:** MAVLink mission end **primary only** → mark **that squad’s** cycle complete; do **not** wait for all squads for one task cycle.
- [ ] **`startTaskExecution` / `buildPrimaryMissionPass`:** support **single-squad** launch (next cycle for one squad); first wave **sequential** per stagger trigger.
- [ ] **`planNextAutoCycleStarts` / delay / between-cycles:** per-squad scheduling; between-cycles dispatch for **that squad’s** primary only when relevant.
- [ ] **Stagger:** implement fixed seconds + waypoint signal path + operator “start next squad” (first wave only) per spec.
- [ ] **Task-level** complete/abort unchanged entry points; **new squad-level** complete/abort APIs + fleet wind-down scoping to one squad’s assignments.
- [ ] Graceful stop / `completeRun` / SIM cleanup: re-read invariants when cycle boundaries are per-squad (`MissionRunReserveSwapMidCycleExecutionInvariantPolicy`, slot evidence, executor batches).
- [ ] Logging: template keys / params for squad-scoped events (`Dagger:1`, slot IDs).

---

## 5 — Scheduling (`MissionRunSchedulingSubsystem`)

- [ ] Deferrals, `activeCycleTaskIDs` guards, `cancelScheduledTaskMissionStarts` — align with per-squad keys.
- [ ] Operator-triggered stagger: wire UI action to scheduling without breaking existing deferral discipline.

---

## 6 — MCS / MC-R UI (`MissionControlSetupView`, running views, sidebars)

- [ ] **One task card**; **per-squad** progress bars + delay / stagger controls where needed.
- [ ] Remove all **execution method** pickers (MV + MCS).
- [ ] Squad-level **complete** / **abort** (immediate + graceful) controls + confirms (`GuardianConfirm` patterns).
- [ ] Live log / chips: sequential **Dagger:1** naming; speaker or params show squad when useful.
- [ ] Task rollup chip copy matches new derivation (executing vs recovery vs aborting).

---

## 7 — Mission Control store & observers

- [ ] `createRun` / `resetToSetup` / persistence: new squad fields if any are stored on run snapshot.
- [ ] Observer / Paladin hooks: expose squad state if required for automation prompts.

---

## 8 — Tests & docs

- [ ] XCTest: per-squad cycle completion ordering; stagger first wave then independent loops; **auto recovery→complete** scenarios (tables above); mixed abort/complete squads.
- [ ] README + `AGENTS.md` pointers: **Mission run state model** updated for squads vs tasks.
- [ ] Retire or redirect overlapping bullets in `TaskRosterAssignmentStatesToDo.md` when squad slot evidence is defined (if applicable).

---

## 9 — Follow-on (not this pass — capture when touching code)

- [ ] Permanent squad delay / bench squad + manual restart (later feature).
- [ ] MRE “re-sync” squads if drift (later).
- [ ] Wingman OFFBOARD/FOLLOW pipeline (separate from MAVLink cycle end).

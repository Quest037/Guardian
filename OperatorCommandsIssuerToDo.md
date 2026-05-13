# Operator commands issuer (MC-R triage) — typed quick dispatch to MRE

**Scope:** Let the operator, from **Mission Control running (MC-R) vehicle triage** (or a tightly related surface), pick a **small curated list** of fleet **catalogue commands** and/or **fleet recipes** via **typeahead + Return**, and have that work executed **for the focused roster assignment’s vehicle** through the same **Mission Run Environment (MRE)** dispatch stack the planner uses — so logs, queue semantics, and audit trails stay coherent.

**Out of scope for v1 (capture elsewhere if product expands):** arbitrary free-text MAVLink; plugin-defined dynamic lists without review; issuing to vehicles **not** bound to the current run’s roster row (use Vehicle Inspector / fleet tools).

---

## Concept (locked until revised here)

| Topic | Working assumption |
|--------|-------------------|
| **Intent** | **Manual override** when autonomous MRE sequencing is wrong, stuck, or too slow — e.g. park / loiter / RTL-style return / mission re-upload+start **after** operator has decided the situation allows it. |
| **Discovery** | **Fixed whitelist** of typed tokens (e.g. `park`, `loiter`, `return`, `missionUpload`); UI offers **prefix typeahead** and **Return** to commit the highlighted match. |
| **Dispatch shape** | Each whitelist entry maps to exactly one ``MissionRunFleetDispatch`` case: ``vehicleCommand``, ``catalogue(name:parameters:)``, or ``recipe(name:parameters:)`` — same union as ``MissionRunIssuedCommand`` today. |
| **Attribution** | Issuer ``MissionRunCommandIssuer/operator`` with ``MissionRunCommandIssuerKey/localOperator`` (or a future stable operator id when accounts exist). |
| **Roster binding** | Commands are issued against the **current** ``MissionRunAssignment`` for the triage row: ``assignmentID``, ``slotName``, ``vehicleTokenKey`` snapshot at enqueue/dispatch time — align with executor **stale token** rules (see ``MissionRunReserveSwapMidCycleExecutionInvariantPolicy`` / queue reconciliation). |

---

## Existing building blocks (do not reinvent)

- **Issued command model:** ``MissionRunIssuedCommand`` + ``MissionRunFleetDispatch`` — `Sources/GuardianHQ/Systems/MissionControl/Models/MissionControlModels.swift`
- **Wire to fleet:** ``MissionRunCommandSubsystem/dispatchCommand`` (vehicle / catalogue / recipe) — `MissionRunCommandSubsystem.swift`
- **Queued execution:** ``MissionRunExecutionSubsystem/enqueueCommandBatch`` + ``MissionRunQueuedCommandBatch`` + ``MissionRunCommandQueueTag`` (`abort`, `complete`, `missionStart`, `reserveSwapPostCommit`) — `MissionRunExecutionSubsystem.swift`, models file above
- **Store API for observers (pattern reference):** ``MissionControlStore/enqueueMissionRunCommandBatch`` requires ``MissionRunObserverPermissions/manageExecutionQueue`` and ``run.lastExecutionContext`` — `MissionControlStore.swift`  
  *v1 product UI will likely need a **first-party** path that does not depend on observer registration unless you intentionally unify on that permission model.*
- **Direct recipe (bypass queue) reference:** ``MissionControlStore/runSingleVehiclePreflightProbe`` / ``runReserveSwapStreamRecipe`` → ``FleetRecipeRunner.shared.run`` — same file; use to understand ``allowDuringLiveMission`` and `source` audit strings.
- **Policy reuse for “what does park mean?”** — ``MissionRunFleetDispatch/preferentialAbortTacticDispatch`` / ``preferentialCompleteTacticDispatch`` / ``betweenCyclesTaskDispatch`` map tactics to catalogue vs recipe; whitelist entries can delegate to these helpers where semantics must match abort/complete/between-cycles.

---

## Open decisions (resolve in implementation pass)

1. **Executor vs immediate**
   - **A — Enqueue** ``MissionRunQueuedCommandBatch`` with an appropriate ``MissionRunQueuedCommandDispatch`` (likely ``immediate`` or ``afterMissionCycle`` per entry) so ``MissionRunCommandSubsystem`` stays the single dispatch choke point and **run log** events match other MC traffic.
   - **B — Direct** ``FleetRecipeRunner`` / ``FleetCommandsCatalogue`` from UI for lowest latency; must still append **consistent** ``MissionRunEvent`` rows if product requires them on the run timeline.
   - *Recommendation:* start with **A** for catalogue atoms + short recipes; reserve **B** only for entries that prove blocked by queue barriers incorrectly.

2. **New queue tag vs reuse**
   - Today’s tags are abort / complete / missionStart / reserveSwapPostCommit. Operator quick commands may need a **new** ``MissionRunCommandQueueTag`` (e.g. `operatorQuick`) so ``cancelMissionRunCommandBatches`` and diagnostics do not conflate with abort or mission start.
   - Decide whether operator quick dispatch is **cancellable** from the same UI strip as “cancel pending mission start” or kept orthogonal.

3. **Session / run gates**
   - Align with other MC-R overrides: which ``MissionRunSessionPhase`` / ``MissionRunStatus`` combinations allow quick dispatch; whether **setup** MCS should mirror the same list (probably not v1).
   - Interaction with **reserve swap** locks and **preflight busy** flags on the same vehicle.

4. **Parameterized entries**
   - **Mission upload + start** requires building parameters (e.g. `missionItemsJSON`) like ``MissionRunExecutionSubsystem`` does for mission start — whitelist entry should point to a **single builder function** that takes `(run, mission, assignment, taskID)` and returns a ``MissionRunIssuedCommand`` or ``MissionRunFleetDispatch``.
   - Fail closed with operator-visible **neutral** errors when the builder cannot produce valid parameters (no roadmap copy — see `.cursor/rules/no-future-version-user-copy.mdc`).

5. **Confirm vs instant**
   - Destructive or wide-area commands (if any appear on the list) may need ``GuardianConfirm`` per `.cursor/rules/guardian-confirm-dialogs.mdc`; **park / loiter** might stay instant Return per product call.

6. **Concurrency**
   - If a **recipe is already running** on that `vehicleID` from Vehicle Inspector or another channel, define whether quick issuer **blocks**, **queues**, or **surfaces a toast** — ``FleetRecipeRunner`` behaviour must be read before shipping.

---

## Implementation phases (checklist)

### Phase 0 — Catalogue & policy layer (pure Swift, testable)

1. [ ] **Whitelist model** — e.g. `enum` or struct table: `token` (typeahead key), `displayName`, `MissionRunFleetDispatch` factory **or** reference to existing ``MissionRunFleetDispatch`` helper; optional ``KeyboardShortcut`` / help string for Theme docs later.
2. [ ] **Gate policy** — pure function: `(runSnapshot, assignment, token) -> Result<MissionRunIssuedCommand, OperatorCommandIssueRejection>` with typed rejections (wrong phase, no fleet token, builder failed, etc.).
3. [ ] **XCTest** — one test per rejection reason + happy path for at least one **catalogue** and one **recipe** token (where tests can run without SITL: use mocks or only dispatch construction + gate, not UDP).

### Phase 1 — MRE / store entrypoint (single choke point)

4. [ ] **API on ``MissionControlStore``** (preferred) or ``MissionRunEnvironment`` — e.g. `issueOperatorQuickCommand(runID:assignmentID:token:) async -> Result<...,>` that:
   - resolves assignment + `vehicleTokenKey` from live run;
   - runs gate policy;
   - either enqueues a batch (new tag + `immediate`) **or** dispatches synchronously through ``MissionRunCommandSubsystem`` (if you add a narrow internal API on the environment);
   - returns structured outcome for toast + log.
5. [ ] **Executor tag** — add ``MissionRunCommandQueueTag/operatorQuick`` (name TBD) if Phase 0 decision #2 requires it; extend ``cancelMissionRunCommandBatches`` call sites only if product cancels these batches.
6. [ ] **Issuer keys** — extend ``MissionRunCommandIssuerKey`` with a stable prefix for quick commands (e.g. `operator.quickCommand`) for log searchability, **or** document reuse of `localOperator` with token in template params.

### Phase 2 — MC-R UI (SwiftUI)

7. [ ] **Placement** — vehicle triage / overlay where roster assignment + `fleetLink`/`sitl` + `run` are already in scope (see ``MissionControlSetupView`` mission live vehicle paths); follow **toolbar / type** patterns in `.cursor/rules/guardian-theme-tokens.mdc`.
8. [ ] **Typeahead** — `TextField` + filtered whitelist; **Return** selects first match; empty / ambiguous states with neutral copy.
9. [ ] **Feedback** — ``ToastCenter`` on success/failure; append or rely on existing ``MissionRunEvent`` template keys for failures (avoid silent failures).

### Phase 3 — Docs & hygiene

10. [ ] **README** — short subsection under Mission Control / floating reserve or “Running console” describing operator quick commands, whitelist location, and gate philosophy (migrate from this file per `.cursor/rules/todo-list-hygiene.mdc` when shipped).
11. [ ] **AGENTS.md** — one bullet pointing at this tracker until the feature lands; then replace with README pointer.
12. [ ] **Theme plugin** (optional) — if a new reusable typeahead chrome is introduced, add a catalog block per `.cursor/rules/guardian-theme-tokens.mdc`.

---

## Suggested starter whitelist (product to trim)

| Token | Maps to (conceptually) | Notes |
|--------|-------------------------|--------|
| `park` | ``MissionRunFleetDispatch/.catalogue(.fleetVehicleDoPark)`` | Same as preferential park tactic. |
| `loiter` | ``.catalogue(.fleetVehicleDoLoiter)`` | |
| `return` / `rtl` | ``.recipe`` return-home registration | Match ``FleetMissionRecipeRegistrations/doReturnHomeRecipeName`` usage elsewhere. |
| `land` | ``.catalogue(.fleetVehicleDoLand)`` | Only if policy allows from MC-R; confirm safety. |
| `missionUpload` / `start` | Recipe + params from plan builder | Highest risk — Phase 0 builder + confirm policy. |

---

## Files likely touched (when implementing)

- `Sources/GuardianHQ/Systems/MissionControl/Models/MissionControlModels.swift` — queue tag, issuer key constants, maybe rejection enum
- `Sources/GuardianHQ/Systems/MissionControl/Store/MissionControlStore.swift` — public issue API
- `Sources/GuardianHQ/Systems/MissionControl/Services/MissionRun/MissionRunExecutionSubsystem.swift` — enqueue / cancel behaviour
- `Sources/GuardianHQ/Systems/MissionControl/Views/MissionControlSetupView.swift` (or extracted subview) — UI
- `tests/GuardianHQTests/*OperatorQuickCommand*` — new test case type

---

## Related trackers

- ``OperatorPromptsTodo.md`` — RoE / consent attribution (orthogonal unless quick commands trigger prompts).
- ``MissionRosterReservesToDo.md`` — reserve swap pipeline (stale token + queue coherence matters for quick issuer after swaps).

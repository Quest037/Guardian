# MC-R ↔ Live Drive handoff (“Engage Live Drive”)

**Purpose:** From **Mission Control running (MC-R)** roster or **floating reserve berth** triage, let the operator **stabilize** a vehicle, **hand off** to **Live Drive** for remote problem solving, then **return** to the same run with roster focus and an explicit **Continue mission** path — without MRE firing **autonomous** work (next-cycle starts, suggests, auto-swaps) against that slot while Live Drive owns the stream.

**Product framing:** Live Drive exists for **remote problem solving** when the vehicle cannot complete the mission on its own. This tracker is the build plan for the **Engage / return** system and MRE coordination.

**Wingmen:** **Not implemented today** — no auto-follow primaries. Treat **wingman rows** as future-only: document the **concept** (stabilisation / authority should eventually apply to the formation), but **v1** can scope to **primary (and any single-slot path)** only until wingman automation lands.

---

## Autopilot: pause vs continue mission (Guardian today)

MAVSDK exposes **`Mission.pauseMission()`** and **`Mission.startMission()`** on the Mission plugin.

| Intent | Guardian surface | Notes |
|--------|-------------------|--------|
| **Pause** mission execution | `FleetVehicleCommand.missionPause` → catalogue `command.fleet.vehicle.do.mission.pause` (`FleetVehicleCoreCommandRegistrations`, `FleetLinkService` → `session.drone.mission.pauseMission()`) | Use for **primary roster vehicle actively running a mission** before Live Drive takeover when product wants autopilot mission state paused (not only MRE queue cancellation). |
| **Continue** after pause | `FleetVehicleCommand.missionStart` → catalogue `command.fleet.vehicle.do.mission.start` (`FleetLinkService` → `startMission()`) | Treat as **“resume mission execution”** after a prior pause **when the stack supports it**; stack quirks remain autopilot-specific. |

**“Continue mission” UI** on return should chain: clear **In LiveDrive** MRE state → optional **mission start** dispatch for that vehicle (if paused) → re-enable executor autostart policy for that task/slot as designed — **verify** on target stacks (PX4 / Ardu) in bench tests.

---

## MRE state: `InLiveDrive` (or equivalent)

**Requirement:** While a roster assignment (or reserve berth binding treated as a dispatchable stream for this feature) is in Live Drive, **MRE must not** schedule or assume autonomous actions for that vehicle: e.g. **next-cycle mission starts**, plan-driven enqueue, reserve auto-suggest / auto-swap evaluators touching that slot, Paladin headless actions, etc.

**Implementation directions (pick one coherent model):**

1. **Per-assignment flag on `MissionRunEnvironment`** — e.g. `assignmentIDsInLiveDriveHandoff: Set<UUID>` (or nested on `MissionRunAssignment` if model changes are acceptable). All autonomous entrypoints **consult** this set before enqueueing or evaluating automation for that `assignmentID` / resolved `vehicleID`.
2. **Mirror on fleet bridge** — optional secondary guard if something bypasses MRE (unlikely for MC-owned paths).

**Executor / autostart:** `MissionRunExecutionSubsystem` already respects `environment.missionTaskAutopilotAutostartSuppressedTaskIDs` when building next-cycle work (`suppressAutostartForTaskIDs`). **Either** insert the task (or tighter assignment scope) into suppression for the Live Drive window **or** gate earlier on the new `InLiveDrive` set — avoid double/conflicting semantics; document the single source of truth.

**Live Drive side:** `FleetLinkService.setLiveDriveControlSessionVehicle` + `setCommandAuthorityGate(.manualTakeover)` already mark **fleet** takeover; MRE must treat **InLiveDrive** as the **run-level** “do not automate this slot” switch.

**Clearing:** On session end **and** on **Continue mission**, clear the flag; on run teardown / reset-to-setup, clear all.

---

## Engage flow (ordered — safety first)

1. [ ] **Primary mission vehicle — pause autopilot mission** (when applicable): dispatch **`missionPause`** (catalogue path above) for that `vehicleID` **via MRE** so onboard mission execution pauses before manual stream. Define “when applicable” (e.g. task in executing state + mission active on autopilot) — pure policy module + tests.
2. [ ] **Cancel pending MRE executor batches** for that run (policy): `MissionRunExecutionSubsystem.cancelPendingCommandBatches(tags:…)` — pass the **full set** of `MissionRunCommandQueueTag` values you intend to drain (`abort`, `complete`, `missionStart`, `reserveSwapPostCommit`) with explicit rules for **reserveSwapPostCommit** (do not leave swap pipeline half-applied). Document ordering vs stabilize (typically **cancel queue after stabilize** or **cancel then stabilize** — pick one and test).
3. [ ] **Set `InLiveDrive`** on the roster assignment (and any linked policy keys such as autostart suppression if used).
4. [ ] **Navigate to Live Drive** — reuse `OperatorPromptReviewFocusController` + `RootView` (`pendingPrimarySection`, `pendingLiveDriveVehicleID`); extend if needed so **`pendingLiveDriveMissionRunID`** is consumed for logging/diagnostics.
5. [ ] **`LiveDriveStore.selectVehicle`** — same `vehicleID` resolution as MC-R (`resolvedFleetStreamVehicleID`).
6. [ ] **Preflight during live mission** — narrow gate: if telemetry satisfies the **park-stable** branch of ``MissionRunEngageStabilizeTelemetryClassifier``, allow `runSingleVehiclePreflightProbe(allowDuringLiveMission: true)` (extend `VehiclePreflightSheet` or add Engage-only preflight path). Otherwise require full Engage stabilisation first.
7. [ ] Operator manually taps **Start session** (existing Live Drive UX) unless product later chains preflight automatically.

**Prompt panel:** Keep `activeMissionRunIDEngagingVehicle` valid (`LiveDriveView` → `OperatorPromptCenter.setLiveDrivePromptPanelHostContext`) — vehicle stays on roster; run stays **running/paused/recovery** as today.

---

## Return flow (MCR)

1. [ ] **End Live Drive session** — existing `endLiveDriveSession` path restores `missionControl` authority gate; extend copy/telemetry as needed.
2. [ ] **Clear `InLiveDrive`** when session ends (and on discard/failed stream paths).
3. [ ] **Navigation** — `pendingMissionControlRunID` + **new** `pendingMissionControlAssignmentID` (or equivalent) consumed by `MissionControlView` / `MissionControlSetupView` to **`focusLiveAssignment`** so the **roster triage** sheet opens on the correct slot.
4. [ ] **“Continue mission”** action card on that triage surface: clears any “handoff paused” flags, optionally dispatches **`missionStart`** for that vehicle if autopilot mission was paused, re-enables MRE autostart / executor policy per slot, appends run log event with issuer `localOperator`.
5. [ ] **Wingmen (future)** — when formation exists, define whether **Continue** applies to squad only or primary-first; stub TODO in code comments only if needed for compile-time hooks.

---

## UI surfaces (reuse patterns)

- [ ] **Live Drive subbar** — “Back to mission” adjacent to Start / End when `InLiveDrive` context from MCR (or `vehicleIsInLiveMission` + no active session); wires focus controller drill-in.

---

## Tests (same coherent pass as feature)

- [ ] `InLiveDrive` gate: assert a known autonomous evaluator / enqueue path **does not** run for a flagged `assignmentID`.
- [ ] Mission pause/start: mock `FleetLinkService` or catalogue response path if available; otherwise integration smoke checklist in README (not SITL in unit tests per repo rules).

---

## Key file references

| Area | Location |
|------|-----------|
| Mission pause / start commands | `FleetVehicleModel.swift` (`missionPause`, `missionStart`), `FleetVehicleCoreCommandRegistrations.swift`, `FleetLinkService.swift` |
| MRE issued dispatch | `MissionControlModels.swift` (`MissionRunIssuedCommand`, `MissionRunFleetDispatch`, `MissionRunEngageStabilizeDispatchKind`), `MissionRunCommandSubsystem.swift`, `MissionRunEnvironment+EngageLiveDriveHandoff.swift` |
| Engage stabilize telemetry | `MissionRunEngageStabilizeTelemetryClassifier.swift`, `FleetVehicleLiveStatusBadgeRow.swift` (`isEngageLoiterLikeFlightMode`), `MissionControlSetupView.swift` (MC-R overlay watch) |
| Executor queue + cancel | `MissionRunExecutionSubsystem.swift`, `MissionControlStore.swift` (`cancelMissionRunCommandBatches`) |
| Autostart suppression | `MissionRunEnvironment.swift` (`missionTaskAutopilotAutostartSuppressedTaskIDs`), `MissionRunExecutionSubsystem.swift` |
| Live Drive session / authority | `LiveDriveView.swift`, `LiveDriveStore.swift`, `FleetLinkService` |
| Navigation drill-in | `OperatorPromptReviewFocusController.swift`, `RootView.swift`, `MissionControlView.swift` |
| Preflight live-mission gate | `MissionControlStore.swift` (`preflightProbeReadinessBlocker`), `VehiclePreflightSheet.swift` |

---

## Hygiene when shipped

Per `.cursor/rules/todo-list-hygiene.mdc`: migrate **locked** decisions into **README.md** (Mission Control / Live Drive section), remove completed bullets from this file, add a one-line pointer in `AGENTS.md` if this file becomes the canonical index (or delete file when empty).

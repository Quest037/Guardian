# Mission roster reserves — swap-in system (MRE / MC)

**Scope:** End-to-end **swap an active primary/wingman for a reserve** while a Mission Control run is live (or in controlled pause), then restore coherent roster + fleet state. Reserves may come from:

1. **Floating reserve pool** — per-task run envelope (`MissionRunEnvironment.reservePoolByTaskID`); see **README.md** → **Floating reserve pool (Mission Control run)** for what exists today (MCS pool row, MC-R triage + map markers, operator swap from **setup**, planner duplicate-token vet, `swapRosterAssignmentWithRandomFloatingReserve` primitive).
2. **Fixed template reserve** — `MissionRosterSlotRole.reserve` on `RosterDevice` / normal `MissionRunAssignment` rows tied via `leaderRosterDeviceId`.

This file tracks **what is not built yet**: the **active swap-in pipeline** (arm/calibrate, mission handoff, reposition, roster mutation, disposition of replaced aircraft, automation & UX). Prefer **one coherent MRE primitive** behind UI, Paladin, and auto-triggers.

---

## Product principles (locked until revised here)

| Topic | Working assumption |
|--------|-------------------|
| **Single abstraction** | “Reserve candidate” = any assignment or pool slot that can supply a **bound, dispatchable** vehicle for a **vacancy** on a task (primary/wingman vacancy); source is either pool row or `.reserve` roster row. |
| **Class match** | Swap is allowed only when **vehicle class** is compatible with the vacancy (see **Vehicle class matching** below). |
| **Map** | Reserves relevant to swap must be **on the live map** when the operator or automation is deciding, or **animate / prompt** so they appear when a swap flow starts (pool aircraft already have markers when hub-linked; fixed reserves same as roster). |
| **Preflight** | Pool aircraft **might** skip **start-run** preflight if product decides it blocks time-to-replace; instead run **swap-time checks** (arm probe, critical calibration subset, mission upload sanity) in the **live swap pipeline**. Document gates explicitly per autopilot stack. |
| **Roster truth** | After success, **MRE** must show the reserve in the **active slot** and the former active in **reserve/pool** (per policy), with `MissionRunEnvironment` + compiled plan + any Paladin/MRE rollups consistent. |

---

## Vehicle class matching

- [ ] **Define compatibility matrix** — e.g. exact `FleetVehicleType` match vs **tier** match (`UGV-W` / `UGV-T` same ground family); document in code + this file when locked.
- [ ] **Mission / vacancy expectation** — read expected class from mission template (roster device `vehicleClass`, task pattern, or slot metadata); reject or rank candidates that fail class gate.
- [ ] **UI** — show **why** a candidate is disabled (“Class mismatch: need multirotor, reserve is fixed-wing”).
- [ ] **Tests** — pure Swift: matrix/tier rules, edge cases (`unknown`, sim vs live).

---

## Swap pipeline (mechanics) — ordered phases

Use one internal state machine or phase enum so UI, logs, and recovery all speak the same language.

### 1 — Pick the reserve

- [ ] **Enumerate candidates** — union of: (a) `availableReservePoolEntries(forTaskID:)` (or superset if policy allows non-“draw-eligible” with warnings); (b) fixed `.reserve` roster assignments on the same task (and/or same squad chain per product).
- [ ] **Ranking** — random (current MRE pool policy), operator-picked, battery-soonest, closest map distance, or Paladin score; pluggable **policy** object.
- [ ] **Dedupe** — same fleet token cannot appear twice on roster + pool (already planner-vetted for mutations; runtime swap must re-check after telemetry delay).

### 2 — Arm and calibrate reserve; handle failures

- [ ] **Minimal swap-time checklist** — which recipes/commands: arm, arm-probe, IMU/compass quick path, RC link, Geofence, etc. (stack-specific tables).
- [ ] **Failure branches** — retry N times, pick next candidate, escalate to operator prompt, or abort swap with rollback plan.
- [ ] **Integration** — `FleetRecipeRunner` / catalogue with clear `assignmentID` / vehicle correlation for the **reserve** stream (not the failing active).
- [ ] **Logging** — structured template keys per phase success/fail (for Paladin + export).

### 3 — Mission upload to reserve (resume / handoff)

- [ ] **Mission slice** — upload **full task mission** vs **partial** from “where active left off” (waypoint index, mission sequence cursor, cycle count); align with MAVLink mission state on active before swap.
- [ ] **Synchronisation** — pause or hold active pattern while upload completes (policy: concurrent vs hard pause).
- [ ] **Verification** — read-back mission count / hash or recipe-based “mission ready” probe on reserve.
- [ ] **Failure** — cannot swap until upload succeeds or operator accepts degraded mode (explicit branch).

### 4 — Move reserve into position

- [ ] **Geometry** — join formation offset, rally to active’s hold point, or “replace in place” if already co-located; use map + hub position.
- [ ] **Commands** — RTL cancelled on reserve, guided/goto, loiter; respect RoE and `MissionRunEngagementDisposition`.
- [ ] **Timeout / proximity** — define “close enough” for handoff (horizontal + vertical tolerances).

### 5 — Roster / MRE status switch (commit)

- [ ] **Atomic commit** — single `MissionRunEnvironment` transaction: move tokens **active ↔ reserve/pool**, update `assignments` (and pool entries) so there is no frame with two primaries or none.
- [ ] **Reuse / extend** `swapRosterAssignmentWithRandomFloatingReserve` or new **`commitReserveSwapIn(activeAssignmentID:reserveSource:…)`** that handles **both** pool and fixed reserve rows.
- [ ] **Recompile plan** — `MissionRunPlannerSubsystem` / `compileInitialPlan`; Paladin callbacks if any.
- [ ] **Derived task state** — `refreshDerivedTaskStates`, session phase, cycle bookkeeping if mid-cycle.

### 6 — Disposition of old active (ex–primary / wingman)

- [ ] **Policy per run** — RTL, move to rally/evac map point, loiter, land here, return to **pool** if battery/health allows (`returnAssignmentToReservePool`), or written-off if not.
- [ ] **Fleet commands** — issue through same catalogue/recipe paths as abort/complete wind-down for consistency.
- [ ] **Telemetry handoff** — UI focuses on new active; old vehicle remains on map until RTB complete or link lost.

---

## Map & situational awareness (UI + data)

- [ ] **Always show** viable reserves when swap UI or escalation is active (highlight, pulse, or filter map).
- [ ] **“Bring onto map”** — if reserve has no position yet, trigger spawn default / operator place / “show last known” from hub history.
- [ ] **MC-R / MCS** — swap wizard or sheet uses **Modal** / **GuardianConfirm** patterns; map column updates live during phases.
- [ ] **Class + battery badges** on candidate list (reuse operational model / `FleetVehicleLiveStatusBadgeRow` patterns where possible).

---

## Preflight vs swap-time checks (pool especially)

- [ ] **Product decision** — document: optional **skip start-run pool preflight** if swap pipeline covers arm/calibrate/mission; or “lite preflight” flag per slot.
- [ ] **Safety minimum** — non-negotiable checks (e.g. armable, GPS, battery not critical) even if full Paladin preflight is skipped.
- [ ] **Mission Control start** — align `orderedStartRunPreflightProbeTargets()` behaviour with new policy (do not double-probe unnecessarily).

---

## Triggers & automation

### Escalation → suggest swap

- [ ] **Recipe / fleet escalation hooks** — when escalation outcome is “needs airframe replacement”, surface **GuardianBottomPromptBanner** or confirm with candidate list if any reserve matches class.
- [ ] **OperatorPromptRouter** — route reserve-swap confirms to MC-R panel (coordinate with Stage D work in **NEXTVERSION.md** if needed).

### Operator manual “swap in reserve”

- [ ] **Entry points** — MC-R task triage, vehicle overlay, roster row overflow, Live Drive (if in scope); single underlying command `MissionRunEnvironment` API.
- [ ] **Confirm** — `GuardianConfirm` with summary of phases and risks.

### Auto: low battery / RTL behaviour

- [ ] **Detect** — policy threshold (battery band, RTL mode, FC failsafe message).
- [ ] **Auto vs suggest** — product: auto-swap only when single unambiguous candidate + all gates pass; else prompt.
- [ ] **Debounce** — avoid thrash on telemetry flicker.

### Paladin / assistant

- [ ] **Paladin** proposes swap with structured args; respects engagement rules.
- [ ] **Logging** — assistant key + template params for audit.

---

## Fixed roster reserve vs floating pool (unify)

- [ ] **Single candidate model** — e.g. `ReserveSwapCandidate: enum { pool(taskID, slotID), roster(assignmentID) }` + shared eligibility pipeline.
- [ ] **Return path** — replaced active goes to **pool** or **fixed reserve row** depending on product; `returnAssignmentToReservePool` vs reassignment to `.reserve` device.
- [ ] **Tests** — both sources through same commit API (mock fleet link).

---

## UI checklist (cross-cutting)

- [ ] **Swap wizard / sheet** — phases with progress, cancel, retry; theme tokens (**README** design system).
- [ ] **Empty states** — no class match, no reserves, all in written-off set.
- [ ] **Toasts + run log** — align with existing `floatingReserveSwapEngaged` style; new keys for each phase.
- [ ] **Accessibility** — labels for map pool markers + roster reserve markers in swap context.

---

## Testing & verification

- [ ] **Unit** — phase machine, class matrix, candidate ordering, rollback when phase 3 fails after phase 2.
- [ ] **Integration (non-SITL)** — mock hub + mission upload state transitions.
- [ ] **SITL smoke (optional later)** — one happy-path swap per stack in `GuardianHQSitlSmokeTests` policy (expensive; defer until stable).

---

## Xcode / SourceKit — reserve-adjacent diagnostics

Xcode’s **Issue Navigator** can list **dozens of red errors** under `MissionControlSetupView.swift` / `MissionRunDetailView` while **`swift build` still succeeds** — symptoms include: `Cannot find type 'MissionRunReservePoolSlot'`, `Cannot find 'MissionControlReservePoolMapMarkerID'`, `Cannot find type 'FleetVehicleLiveStatusBadgeRow'` / `liveStatusBadgeRow`, `trafficLightIconTint` missing on `FleetVehicleBatteryTrafficBand`, `Referencing subscript 'dynamicMember:' requires wrapper 'ObservedObject'`, `Cannot call value of non-function type`, key-path inference failures. Those symbols **do exist** in the SwiftPM target; the drift is almost always **indexer / very large file** pain, not missing source files.

- [ ] **Reproduce vs SwiftPM** — on the same commit, confirm `swift build` and (when run) `swift test` are green; capture whether issues are Xcode-only.
- [ ] **Operational mitigations** — Clean Build Folder, delete project DerivedData, restart `SourceKitService`, re-open package; confirm no duplicate/off-target copies of `MissionControlSetupView.swift`.
- [ ] **Structural mitigations** — if false positives persist: **split** `MissionControlSetupView.swift` (move `MissionRunDetailView` + reserve/map helpers into dedicated files), keep **one public import surface** per extension file so SourceKit’s partial AST stays coherent; re-audit `@ObservedObject` custom `init` wiring (`_property = ObservedObject(wrappedValue:)`).
- [ ] **Document** — once the team picks a stable approach, add a short **“MC-S megafile + Xcode”** note to **README.md** or **AGENTS.md** so new contributors do not chase phantom errors.

---

## Dependencies & references

- **Shipped today:** README **Floating reserve pool**; `swapRosterAssignmentWithRandomFloatingReserve`; planner reserve-token vet; MC-R pool UI + map markers (`MissionControlReservePoolMapMarkerID`).
- **Xcode false reds on `MissionControlSetupView`:** see **Xcode / SourceKit — reserve-adjacent diagnostics** above (resolve or document mitigations).
- **Deferred ideas (broader):** **NEXTVERSION.md** → **Floating reserve pool — deferred phases** (2026-05-12) — merge or extend when this roster swap-in work lands.
- **Related tracker:** `TaskRosterAssignmentStatesToDo.md` — assignment/slot lifecycle state may feed “phase 5 commit” and auto-triage; keep in sync when slot state enum exists.
- **Engagement / RoE:** `MissionRunEngagement` + disposition when issuing goto/RTL during swap.

---

## Implementation order (suggested)

1. Candidate model + class matrix + enumerate API (no UI).  
2. Manual operator swap happy path (fixed reserve first, then pool) with confirm + commit + plan recompile.  
3. Mission upload + reposition phases (reuse execution subsystem patterns).  
4. Arm/calibrate swap-time recipe bundle + failure handling.  
5. Map UX + “bring onto map”.  
6. Auto-triggers + escalation suggestions + Paladin.  
7. Hardening, tests, docs migration into **README.md** when behaviour is stable (then trim this file per todo hygiene).

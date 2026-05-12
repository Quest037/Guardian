# Mission roster reserves — swap-in system (MRE / MC)

**Scope:** End-to-end **swap an active primary/wingman for a reserve** while a Mission Control run is live (or in controlled pause), then restore coherent roster + fleet state. Reserves may come from:

1. **Floating reserve pool** — per-task run envelope (`MissionRunEnvironment.reservePoolByTaskID`); see **README.md** → **Floating reserve pool (Mission Control run)** for what exists today (MCS pool row, MC-R triage + map markers, operator swap from **setup**, planner duplicate-token vet, `swapRosterAssignmentWithRandomFloatingReserve` primitive).
2. **Fixed template reserve** — `MissionRosterSlotRole.reserve` on `RosterDevice` / normal `MissionRunAssignment` rows tied via `leaderRosterDeviceId`.

This file tracks **what is not built yet**: the **active swap-in pipeline** (arm/calibrate, mission handoff, reposition, roster mutation, disposition of replaced **vehicle**, automation & UX). Prefer **one coherent MRE primitive** behind UI, Paladin, and auto-triggers.

---

## Product principles (locked until revised here)

| Topic | Working assumption |
|--------|-------------------|
| **Single abstraction** | “Reserve candidate” = any assignment or pool slot that can supply a **bound, dispatchable** vehicle for a **vacancy** on a task (primary/wingman vacancy); source is either pool row or `.reserve` roster row. |
| **Class match** | Swap is allowed only when **vehicle class** is compatible with the vacancy (see **README.md** → **Floating reserve pool** → class substitution + MCS roster swap help). |
| **Map** | **Floating pool** markers on the live overview map are **hub-linked** (same as roster). **Mission Control start** preflight already required pool aircraft to have a usable position; there is no separate “bring onto map” path, and pool rows are not cleared in-app to swap a failed airframe yet — treat loss of telemetry as **fleet / hub** recovery, not this tracker. |
| **Preflight** | Pool aircraft **might** skip **start-run** preflight if product decides it blocks time-to-replace; instead run **swap-time checks** (arm probe, critical calibration subset, mission upload sanity) in the **live swap pipeline**. Document gates explicitly per autopilot stack. |
| **Roster truth** | After success, **MRE** must show the reserve in the **active slot** and the former active in **reserve/pool** (per policy), with `MissionRunEnvironment` + compiled plan + any plugin-assistant / MRE rollups consistent. |

---

## Swap pipeline (mechanics) — ordered phases

Use one internal state machine or phase enum so UI, logs, and recovery all speak the same language.

### 1 — Pick the reserve

Handled in product today — see **README.md** → **Floating reserve pool** (``enumerateReserveSwapCandidates``, ``MissionRunReserveSwapRankingPolicy``, MCS ``swapRosterAssignmentWithRandomFloatingReserve``, pre-commit dedupe / operational re-check).

### 2 — Roster / MRE status switch (commit)

Locked contracts (atomicity, commit routing, plan recompile + plugin assistants, **mid-cycle queue / cycle-counter invariants**) live in **README.md** → **Floating reserve pool** and the `MissionRunReserve*` policy types under Mission Control models. Executor wiring for live swap-in builds on those contracts.

### 3 — Disposition of old active (ex–primary / wingman)

Locked contracts (**pool / written-off**, **fleet wind-down via catalogue + recipes**, **MC-R + map handoff**) live in **README.md** → **Floating reserve pool** → **Reserve swap disposition of replaced active** and ``MissionRunReserveSwapReplacedActive*`` policy types in `MissionRunReserveSwapReplacedActiveDispositionPolicy.swift`. Executor wiring issues the actual post-swap commands and UI focus.

---

## UI checklist (cross-cutting)

- [ ] **Swap wizard / sheet** — phases with progress, cancel, retry; theme tokens (**README** design system).

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
- **Related tracker:** `TaskRosterAssignmentStatesToDo.md` — assignment/slot lifecycle state may feed “phase 2 commit” (roster / MRE switch) and auto-triage; keep in sync when slot state enum exists.
- **Engagement / RoE:** `MissionRunEngagement` + disposition when issuing goto/RTL during swap.

---

## Implementation order (suggested)

1. Candidate model + class matrix + enumerate API (no UI).  
2. Manual operator swap happy path (fixed reserve first, then pool) with confirm + commit + plan recompile.  
3. Mission upload + reposition phases (reuse execution subsystem patterns).  
4. Arm/calibrate swap-time recipe bundle + failure handling.  
5. Map presentation (MC-R / MCS).  
6. Auto-triggers + escalation suggestions + Paladin.  
7. Hardening, tests, docs migration into **README.md** when behaviour is stable (then trim this file per todo hygiene).

# MCS — reserve pool map home (bulk SIM staging)

**Purpose:** On **Mission Control setup (MCS)**, let the operator set a **common hub / map pose** for **all floating-reserve pool SIMs** on a **task** in one action — without placing dozens of draggable vehicle markers (bad UX at N = 10–40).

**Menu copy (locked):** **Set reserve pool home** (task header overflow).

**Scope:** MCS **Rosters** staging map + task chrome only for this pass. **MC-R** pool map behaviour stays separate unless explicitly unified later.

---

## Locked product decisions

| # | Topic | Decision |
|---|--------|----------|
| 1 | **Who moves** | **SIM / SITL pool rows only** — same token class as today’s per-roster **`applySetupMarkerDrag`** path (`FleetMissionVehicleToken` → `.sitl`). Skip empty berths, live-linked aircraft, and rows without a resolvable SITL instance + stack. |
| 2 | **Geometry** | **Same lat/lon for every eligible pool SIM** for v1 (no per-aircraft offset grid). |
| 3 | **Feedback** | **Do not** toast a definitive “all succeeded” / counts-after-hub-settles — SITL reposition + hub catch-up is **async**. Prefer a **single immediate ack** that sets expectation (e.g. placement requested for **N** pool SIMs; positions update as telemetry reflects) **or** a **mode banner** on the Tasks card / map chrome; avoid implying synchronous completion. |
| 4 | **Cancel** | **Yes** — leaving the mode without applying: second tap on the menu affordance, **Esc** (where macOS focus allows), **background map tap** (align with `clearStagingSetupMapSelectionFromBackgroundTap` patterns), and **task switch / teardown** should all **disarm** safely. |
| 5 | **Label** | Menu item title: **Set reserve pool home**. |
| 6 | **Preview** | **Cursor-following preview ring** (or equivalent Leaflet overlay) while armed — reuse existing map “armed placement” cues where possible (`missionPointPlacementArmed` drives cursor styling in `OSMMapView`; extend model/JS or add a sibling flag for **pool-home placement** so mission-point arm and pool-home arm stay mutually exclusive). |
| 7 | **Undo** | **None** for v1. |
| 8 | **After apply** | **Fit map** to visible mission content including updated pool SIM positions (same bbox helper family as `fitSetupStagingMapToVisibleMissionContent` / `MissionControlLiveMapFitCoordinates` once markers or hub digest reflects new poses — may require a **post-batch delayed fit** or fit-from-hub after a short debounce so Leaflet has fresh coords). |

---

## UX flow (operator)

1. Operator opens the **task** row overflow (**ellipsis** `Menu`) on the MCS roster task header (exact host view TBD — likely the per-task header inside the Rosters accordion next to existing task actions).
2. Chooses **Set reserve pool home** → app enters **armed** state for **that `taskID` only**.
3. Staging map shows **preview ring** at cursor (or crosshair + ring); cursor **pointer**; optional one-line instruction in map chrome or toast: “Click map to set pool SIM home for &lt;task&gt;.”
4. **First map click** (lat/lon): enqueue **`applySimState`** (or equivalent) for **each** eligible pool berth on that task **at the same coordinate**; then **disarm**, **clear preview**, run **fit map**.
5. **Cancel** disarms with no fleet writes.

**Mutual exclusion:** Arm state must interact cleanly with existing MCS map exclusivity — **roster vehicle selection** (`setupSelectedAssignmentId`), **task path selection** (`setupStagingMapSelectedTaskPathID`), **mission point selection / placement** (`setupRostersSelectedMissionPointID`, `missionPointPlacementArmed`), and **SIM drag overlays** (`setupStagingSimDragCoordByAssignmentID`). Document the single **“clear peer state when arming pool-home”** rule (mirror `toggleStagingVehicleMapSelection` / `clearStagingSetupMapSelectionFromBackgroundTap`).

---

## Implementation anchors (codebase)

| Area | Likely touchpoints |
|------|-------------------|
| **Pool rows + synthetic fleet row** | `MissionRunAssignment.syntheticForReservePool(slot:)` (`MissionControlModels.swift`); `run.reservePool(forTaskID:)`; MCS strip `taskFloatingReservePoolStrip` / `reservePoolSlotCard` in `MissionControlSetupView.swift`. |
| **Per-SIM pose write** | `applySetupMarkerDrag(markerID:lat:lon:)` + `fleetLink.applySimState` + `MissionRunStagingSimDragOverlay` reconcile — **reuse the same stack resolution** (SITL instance → systemID → `vehicleID` → autopilot stack guard) in a **shared helper** callable from both single-drag and **batch pool-home**. |
| **Staging map** | `rostersStagingMapBare` / `GuardianMapView` wiring: `onMapClick`, `onVehicleMarkerMoved`, `onVehicleTap`; `pushSetupStagingMapModelFromMissionTemplate` / `setupStagingMapMarkerCoordinateDigest` / `SetupStagingMapStructureIdentity` if pool topology must bump structure identity when only tokens change. |
| **Map model** | `GuardianMapModel` / `GuardianRouteMapGeometry` — may need a **new published field** for pool-home cursor preview (lat/lon + radius) **or** extend Leaflet bridge with a lightweight “ghost circle” API parallel to `headingPreview`. |
| **Leaflet** | `OSMMapView` / embedded JS — `setMissionData` and cursor rules; any new preview likely needs **JS + Coordinator** plumbing similar to existing previews. |
| **Tests** | Pure-Swift: filtering “eligible pool SIM count” from a fixture `MissionRunEnvironment` + `MissionRunReservePool`; optional policy test for “skip live / skip unbound”. UI defer to manual unless a small helper is extracted. |

---

## Build phases (ordered)

### Phase A — State + exclusivity

- [ ] Add `@State` (or nested model) for **pool home placement arm**: e.g. `mcsReservePoolHomePlacementTaskID: UUID?` (nil = off).
- [ ] Centralise **disarm** + clear preview + restore cursor.
- [ ] On **arm**: clear competing MCS map selections per table above; on **disarm** from cancel only, no fleet I/O.

### Phase B — Task header UI

- [ ] Add **ellipsis `Menu`** to the **MCS per-task header** (confirm exact SwiftUI host — task accordion row that already shows task name / expand chevron / related controls).
- [ ] Menu action **Set reserve pool home** → validates task enabled + at least one **eligible SITL** pool row; if zero, toast **warning** / inline copy (current product voice rules).
- [ ] If already armed for same task → treat as **toggle off** (cancel).

### Phase C — Map: preview + click

- [ ] While armed: **pointer** cursor; **preview ring** following map mouse move (desktop) — wire from `GuardianMapView` / `OSMMapView` **mousemove** or SwiftUI overlay if map exposes center-only; prefer **one** approach consistent with Leaflet stack.
- [ ] **Map click** when armed: read lat/lon from `onMapClick` **or** dedicated handler that runs **before** background-clear if needed — ensure **click applies pool-home** and does not only clear selection (ordering bug risk).
- [ ] **Background tap** when armed: **cancel** arm (and existing clear-selection behaviour if still desired).

### Phase D — Batch apply

- [ ] Implement **`applyReservePoolHomeForTask(taskID:lat:lon:)`** (name illustrative): iterate `run.reservePool(forTaskID: taskID).entries`, filter **SIM/SITL** + resolvable instance + non-unknown stack; for each, build `FleetSimState` (reuse yaw/alt pattern from `applySetupMarkerDrag`).
- [ ] **Concurrency:** sequential `await fleetLink.applySimState` vs limited parallelism — pick one; avoid hammering 40 simultaneous if bridge is fragile; document choice.
- [ ] **Persistence:** confirm whether run envelope must be **saved** after batch (`onUpdate(run)` / mission store) same as other MCS mutations.

### Phase E — Feedback + fit

- [ ] **Toast / banner:** immediate operator ack per decision **#3** (no false “all done”).
- [ ] **Fit map** after apply (`fitSetupStagingMapToVisibleMissionContent` or variant including pool markers if pool markers are added to digest by then — see Phase F).

### Phase F — Optional follow-ups (not v1 unless needed)

- [ ] **MCS map markers** for pool SIMs (separate from bulk-home) — see prior analysis: `setupVehicleMarkers` today is **assignments-only**; adding markers improves fit-before/after without relying solely on hub delay.
- [ ] **Structured log** line per batch (template key) for supportability.

### Phase G — Keyboard + lifecycle

- [ ] **Esc** cancels arm when map or task panel has focus — align with `GuardianChromeInteraction` / existing MC confirms if any pattern exists.
- [ ] Disarm on **tab away**, **run status change**, **mission template loss**, **task disabled**.

---

## Non-goals (v1)

- Per-aircraft offset / spread from one click.
- Undo / revert snapshot.
- Moving **live** pool aircraft from MCS.
- Paladin / headless API for the same action (could mirror later).

---

## README / hygiene

When the feature ships: add a short subsection under **Mission Control setup** or **Floating reserve pool** in `README.md` (operator-facing behaviour + arm/cancel + “telemetry lags” note), then **remove** completed checklist noise from this file per `.cursor/rules/todo-list-hygiene.mdc` (migrate durable decisions to README, delete done bullets).

---

## Open questions (resolve during implementation)

- **Exact header host** for the ellipsis menu (per-task row vs mission-level) — pick the control that is always visible when editing that task’s roster + pool.
- **Whether** to show a **bottom banner** on the staging map card while armed (stronger than toast for mode indication).
- **fit map** timing: immediate vs `Task.sleep` 200–500ms post-batch to let first hub samples land (measure on SITL stack).

# Mission Points — implementation backlog

Typed **map points** on missions (not path waypoints): generic pin + **kind** (rally, extraction, …) + metadata. **MRE** is the consumer of semantics; vehicles receive ordinary movement commands—points stay **soft** (no autopilot rally upload / FC binding in v1). Detail stays here; high-level bullets remain in **`TODO.md`** § Mission Mechanics.

---

## 0 — Principles

| Principle | Decision |
|-----------|----------|
| Relationship to **task path** | Points are **orthogonal** to `MissionTask` route waypoints; they are individual annotations. |
| Relationship to **vehicles** | **No** per-point vehicle binding. A point is an **abstract coordinate** (and metadata); MRE decides which asset references which point when issuing commands. |
| **Soft** vs **hard** | Points and kinds are for **MRE / operator / plugins** to reason about. **Do not** push points into FC rally tables or similar until a deliberate **fleet bridge** exists (`do.move.point` `rally` / `home` remain unwired today). |
| **Conflict resolution** | **Last write wins** for concurrent edits (operator, MRE, plugin). Operator can constrain behavior via **RoE** (pre-run and during run). |
| **Catchment** | **`catchmentRadiusM`**: allowed **1…1000** metres, **default 10**. MRE uses this circle for “arrived at point” / deconflict intent—avoids pile-ups when many drones target one coordinate. (Other spatial fields on a point remain optional later; catchment is the v0 spatial knob.) |

---

## 1 — Data model (two layers)

### 1.1 Template layer (mission document)

**Shipped (step 1 — models + persistence + cascade):** `MissionPointKind`, ``MissionPoint``, ``Mission/missionPoints`` on `Mission` (JSON key `missionPoints`); ``Mission/removeMissionPoints(forRemovedTaskID:)``; task delete in Mission workspace calls that cascade; clone copies points with new row ``MissionPoint/id``. Tests: `MissionPointTests`. Locked rules remain below for UI/MRE work.

- **Persistence:** A **single list** on the mission model (e.g. `Mission.missionPoints`); each row includes optional **`taskID: UUID?`** — **`nil`** = **mission-wide**; non-`nil` = **scoped to that task**. Operator toggles scope by setting/clearing `taskID` when creating or editing.
- Points **persist on the mission** alongside tasks, roster, etc.
- **Kind:** Extensible type enum (minimum v1: `rally`, `extraction`; room for more). Kind drives **metadata schema** extensions later.
- **Identity:** Stable **`point_id`** (slug) for MRE, recipes, and logs; distinct from display label.
- **Human label** vs **map chip:** e.g. human **“Rally Point A”** / **“Extraction Point C”**; on-map compact **“RP:A”** / **“EP:C”** (pattern: kind prefix + short id).
- **Catchment:** `catchmentRadiusM: Double` — **default 10**, allowed range **1…1000** (inclusive); validate on save and on MRE edit.
- **Lifecycle:** If a **task is deleted**, all points whose **`taskID`** equals that task are **removed** from the list. Mission-wide rows (`taskID == nil`) are unaffected.

### 1.2 Run layer (Mission Control / MRE)

**Shipped (envelope + mutations + logs):** ``MissionRunEnvironment/runtimeMissionPoints`` is seeded from ``Mission/missionPoints`` on run init and on ``updateTemplate(_:)`` while ``MissionRunStatus/setup`` (or when the mission id changes); after the run leaves setup, template refreshes **do not** replace the envelope so live rows persist. APIs: ``MissionRunEnvironment/applyRuntimeMissionPointCreate(_:source:)``, ``applyRuntimeMissionPointUpdate(id:source:mutate:)``, ``applyRuntimeMissionPointSetClosed(id:isClosed:source:)`` (no delete). Structured log keys: ``MissionRunLogTemplateKey/missionPointRuntimeSeeded`` … ``missionPointRuntimeClosedChanged`` (catalog + tests: ``MissionRunEnvironmentMissionPointsTests``).

- When a run is **set up and executed**, template points are **carried into MC** the same way task context is—operators and MRE see a **run-time envelope** that includes point state.
- **MRE mutations** (create, edit, close/reopen) apply to the **live run**, **not** to rewriting the saved mission template on disk. Persist run snapshots / logs separately; merging “what the operator saved” vs “what happened on run” is a product decision for export—document in README when shipped.
- **MRE may not delete** a point from the run envelope (only template delete in Mission editor, or explicit product rule later). **Close** / **reopen** instead of delete for soft retirement.

---

## 2 — Mission editor (Mission workspace → **Tasks** tab)

**Shipped (v0 — Tasks tab):** Segmented **Tasks / Points** under the workspace Tasks tab. Map shows **diamond** markers with **ordinal digit only** on the pin at all times (hue = rally vs extraction; selection uses larger diamond / border, not a longer label); drag-to-move; Points tab toolbar **mappin** to arm tap placement; new points default at **map viewport center** without bbox refit from point-only changes; **Add point** selects the new row and **scrolls** it into view in the sidebar list; context menu **Delete map point** + ``GuardianConfirmDanger``; slug ``Mission/renumberMissionPointSlugsByListOrder()`` (`rally.1`… / `extraction.1`… by list order); edit in **AppDrawer** (kind, scope, catchment, closed). ``MissionPoint/mapChipLabel`` remains for lists / drawer; ``mapGlyphDigit`` on map; tests in ``MissionPointTests``.

- **Clustering:** **Nice-to-have** when many markers overlap (deferred if costly in v1).

---

## 3 — MRE contract

- Points are **first-class** in the MRE world model: readable, filterable, **mutable at runtime** by MRE and **plugins** (subject to RoE).
- **API surface (conceptual):** **create**, **edit** (coordinates, label, catchment, kind-specific fields, closed flag). **No delete** from MRE—use **closed** to retire.
- **Closed:** Point excluded from decision-making until **reopened**. Reopen path: **operator** directly, or **MRE/plugin** via **operator prompt** (ties to RoE / “new rule of engagement” flow).
- **Recipes:** Missions/recipes **reference** point ids in vocabulary only in early phases (e.g. `point.rally.<id>`); **recipe DSL does not execute** point logic—MRE interprets and issues concrete fleet commands. Expand when recipe catalogue gains predicates/commands.

---

## 4 — Mission Control Run (MCR)

### 4.1 Map

- **Shipped:** MC-R **live overview** map and **setup roster staging** map draw **runtime** mission points as the same diamond markers as the mission editor. **Live overview:** tap a point in the **Map points** list or on the map to select it; the selected pin is **draggable** (coordinate updates via ``MissionRunEnvironment/applyRuntimeMissionPointUpdate`` + ``onUpdate(run)``). **Setup staging:** unchanged (template points, MCS Points tab). **Filter:** when a **task triage** sheet is focused, show **mission-wide** (`taskID == nil`) **plus** points scoped to that task; when no task focus, show **all** points. Pure filter: ``MissionPoint/filteredForMissionControlLiveMap(_:focusedTaskID:)``.

### 4.2 Points overlay

**Shipped (v0):** Slide-up **Map points** panel over the MC-R **Tasks** card (`fullCardOverlay` stack, **topmost** over task triage / vehicle overlays). **Trigger:** MC-R run sub-bar (**mappin**), beside run controls — not on the map toolbar. **Header:** title + plain **plus** glyph (overlay stack style) + close; **no** subtitle strip. **Add:** one tap creates a **rally** at the live map centre (else mission home else `0,0`), default catchment, scope = focused task when set; ``applyRuntimeMissionPointCreate`` assigns the next numeric `rally.n` / `extraction.n` slug (same scheme as the Missions list), **selects** the new point for map drag, and **scrolls** its list row into view (no automatic edit drawer). **Filter** for list + map matches §4.1. **Rows:** tap row toggles map selection (primary border); chip + kind, **Closed** toggle (``applyRuntimeMissionPointSetClosed``), **pencil** → edit drawer. **Closed** rows: muted + strikethrough chip. Panel clears when the run returns to **setup** / **completed** or session **aborting**.

- **Clustering / map placement mode:** unchanged nice-to-have from §2.
- **Permissions / RoE gates** for who may add or reopen: not split here — follow Rules-of-Engagement product path when wired.

---

## 5 — Logging & observability

- **Mandatory:** Structured log events for **create / edit / move / close / reopen** with **`point_id`**, **kind**, **scope**, **source** (operator | mre | plugin id), **run id**, and **before/after** summary where useful.
- Tie into existing **Mission Run** log / MCR export story so post-run forensics can replay point state changes.

---

## 6 — Mission Control Setup (MCS) / Tasks tab

- **Layout:** Same split as Mission workspace **Tasks** tab: staging **map left** (~70%), **right column** with a **segmented Tasks | Points** control.
- **Tasks:** Existing roster accordions, per-task SIM spawn wand, and slot cards (unchanged).
- **Points:** Edit the **mission template** list (`Mission.missionPoints`) while the run is in **setup**: list rows (tap = map selection only), **pencil** opens ``MissionWorkspaceMissionPointEditDrawer`` in ``AppDrawer`` (kind, scope, catchment, closed), **trash** + map context menu use ``GuardianConfirmDanger`` before delete. **Add point** uses the map viewport centre when known, otherwise ``RouteCoordinate()``; **selects** the new point and **scrolls** its row into view; a selected point may **drag-move** on the map (no separate map toolbar on MCS). Writes go through ``MissionStore`` + ``MissionRunEnvironment/updateTemplate(_:)`` so ``runtimeMissionPoints`` stays aligned; after structural edits call ``Mission/renumberMissionPointSlugsByListOrder()``.

---

## 7 — Testing (same pass as features when implementing)

| Layer | Tests |
|-------|--------|
| Pure model | Encode/decode, `taskID` nil vs set, task-delete cascade, `catchmentRadiusM` default **10** and clamp **1…1000**, `point_id` uniqueness rules. |
| Merge / LWW | Deterministic last-write semantics for conflicting edits (fixture clock or monotonic version). |
| MRE API | Contract tests for create/edit/close/reopen; no-delete invariant. |
| Filtering | MCR overlay filter given selected task id vs nil (`MissionPointMissionControlLiveMapFilterTests`). |

Skip SwiftUI pixel tests unless extracting pure layout helpers.

---

## 8 — Non-goals (initial phases)

- Binding vehicles to points in the data model.
- Uploading points as **ArduPilot rally** / **MAVLink rally items** without a dedicated fleet epic.
- **Geofenced** regions, corridors, time windows (separate **Mission Task.geofence** backlog).
- Automatic **recipe execution** from point types (MRE only until recipes gain verbs).

---

## 9 — Locked decisions (v0)

1. **MCR filter — no task selected:** show **all** points (mission-wide + every task-scoped row).
2. **`catchmentRadiusM`:** range **1…1000** m, **default 10** (no `0` sentinel—store a real value).
3. **Mission persistence:** **one list** on the mission; each point has **`taskID: UUID?`** (`nil` = mission-wide).

---

## 10 — Related

- **`TODO.md`** — Mission Mechanics → Points / Rally / Extraction bullets.
- **Fleet (future bridge):** `FleetVehicleCoreCommandPointKind.rally` / `home` — today `.notImplemented` in `FleetCommandStackConverterShared.translateMovePoint` until hub readback exists.
- **Operator prompts / RoE:** close/reopen and permission gates for MRE/plugin edits.

---

## 11 — MCR / MRE RoE follow-ups (not shipped)

- **Move / drag live map point:** When vehicles are **actively navigating** toward a runtime map point, MRE should detect coordinate changes, consider **reroute / replan**, and surface an **operator confirm** (Rules of Engagement) before or after applying the move — today only logging + persistence runs.
- **Close / reopen runtime point:** When a point is **closed** (or reopened) while in use as an active rally/extraction target, MRE should evaluate in-flight bindings, **reroute or hold** as policy dictates, and prompt the operator under RoE — today ``applyRuntimeMissionPointSetClosed`` logs + updates state only.

---

*Last updated: Mission Points subsystem spec + backlog seed.*

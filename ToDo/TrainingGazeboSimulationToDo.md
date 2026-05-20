# Training app — Gazebo worlds, World Builder, and Training lab

Goal: **Guardian Training** is an autonomy lab with three cooperating surfaces:

1. **Worlds (Builder)** — author, validate, and save training environments (Gazebo scenes + anchors). **No vehicles** in the Builder Gazebo viewport — world geometry only.
2. **Training lab** — one combined lab (no separate Vehicle vs Formation products). Pick a **built** map; roster is always **squads** (a squad of one is normal); run sessions on the `.run` Gazebo world with PX4 SITL + sized vehicle proxies.

**Product model (locked):**

| Concept | Rule |
| --- | --- |
| **Unified lab** | ``TrainingLabPanelView`` + ``TrainingLabController`` (teaching + formation follow are implementation façades, not separate operator modes or tabs). |
| **Squad of one** | Every vehicle lives in a **squad** (primary only = squad of 1). Teach skills with **only that vehicle** in the roster so control/scoring stay simple. |
| **Wingmen** | Add wingmen when ready for multi-vehicle formation; same squad vocabulary and start/end slot layout either way. |
| **v1 transit (no waypoints)** | Each squad goes **start zone → end zone** and must finish in the authored **end formation** slot boxes (mission-like, but no intermediate waypoints yet). |
| **All squads on Run** | **Every** squad with linked sims transits and is **brain-controlled**. Only the **learning** squad is being *trained* (skill promotion / evaluation). Other squads run **simple tasks** the brain already performs well (supporting cast, not the teach target). |
| **UGV motion v1** | **Squad of one (primary only):** **Nav2 per vehicle** to its **end slot** pose. **Wingmen (later):** hybrid — each vehicle reaches its end slot **while** maintaining formation en route (revisit primary+follow vs per-vehicle Nav2 when wingmen ship). |
| **Later** | Ordered **waypoints** with per-stop jobs (formation, spacing, dwell, tasks) — see Phase 4d. |

**Heading note (document now, implement with waypoints):** A formation’s **group heading** (anchor / gold rim on the map) is not always the **yaw of every vehicle** in the formation (e.g. reverse-into-slot, sideways approach). v1 end slots may align group + slot yaw; per-waypoint slot headings come later.

**Today:** **Worlds** + World Builder with embedded 3D viewport (headless `gz sim -s` + websocket + `gzweb` in-panel). **Training lab** loads the same stack for `.run` when a map is chosen. Formation slots, staging, `buildMap`/`resetMap`, spawn alignment, **v1 transit run** (orchestrator + open-loop ``TrainingLabTransitMotion`` + end monitor + safety), and **leave-tab** persistence are shipped. **Not yet roadtest-ready:** SITL motion in sim may not match operator expectation; Gazebo proxies are **spawn-only** (no telemetry-driven `set_pose`); Nav2 is **plan overlay + geodesic fallback** on drive, not ``navigate_to_pose`` execution.

**v1 delivery order (locked):** motion + visible sim truth → Nav2 plan on **Run** → proxy follows MAVLink → Nav2 execute (or proven open-loop) → roadtest failure matrix → **then** metrics / teaching / templates / waypoints. See **v1 critical path** below.

**Cross-links:** `README_FULL.md` → **Gazebo training simulation**, **Unified Training lab**; **Two-app SwiftPM products**; **`ToDo/GazeboAppWideInstanceToDo.md`** (single headless `gz sim`, world swap); `Sources/GuardianHQ/Resources/Ros2VehicleBridge/README_AUTONOMY.md` (Nav2 rollout).

---

## v1 critical path (roadtest order)

**Scope for first roadtest:** one **squad of one**, **PX4 UGV**, **flat** map with placed start/end zones. Multi-squad, costmaps, terrain, and collision groups wait until this lane passes.

| # | Goal | Tracker |
| --- | --- | --- |
| 1 | **Vehicle actually moves** — ``Run`` drives SITL via training control segments (or first execute path); pose changes in fleet hub; end-slot evaluator sees real arrivals/failures. | Phase 7 → **Motion proof** |
| 2 | **Nav2 plan on Run** — global plan start slot → end slot when ROS sidecar is up (not map-idle overlay only); path feeds drive + along-path stuck monitor. | Phase 7 → **Nav2 plan on Run** (code shipped; confirm `nav2` source on roadtest) |
| 3 | **Gazebo proxy follows sim** — vehicle meshes update from hub position/heading (``set_pose`` or equivalent), not spawn pose only. | Phase 7 → **Proxy telemetry sync** |
| 4 | **Execute or tighten open-loop** — ``navigate_to_pose`` / cmd_vel (locked UGV strategy) **or** prove open-loop segments sufficient for end-zone pass/fail on flat maps. | Phase 7 → **Nav2 execute** |
| 5 | **Roadtest matrix** — planner down, timeout, stuck, bad goal, sidecar late; **light run logs** (pose trace, path source, segment acks) — instrumentation, not scoring. | Phase 7 → **Roadtest instrumentation** |
| 6 | **End of v1** — teaching loop metrics, templates (4b), waypoints (4d), skills promotion. | **End of v1** |

**Explicitly not blocking step 1–5:** Phase 4 **Teaching loop**, Phase 4b templates, Phase 4d waypoints, Phase 6 multi-squad collision/scale (except one `.run` world already shipped).

---

## Phase 3b — World Builder viewport (shipped)

- Embedded panel: `GazeboWebViewportView` + offline `dist/gzweb.bundle.mjs` (`make gzweb-viewer` to regenerate).
- Preview / Build use server-only sim + Harmonic websocket bridge (not a separate Gazebo window).
- **Dev prerequisite (macOS Homebrew):** `brew install libwebsockets && brew reinstall gz-launch7` then `make gazebo-runtime` — without `libgz-launch-websocket-server.dylib`, `gz launch` cannot serve gzweb (sim server still runs).

---

## Phase 4 — Training lab: vehicle in environment

- [x] **Embedded 3D viewport** — same stack as World Builder in Training lab (`GazeboSessionLaunchPolicy` + `TrainingLabPanelView`).
- [x] **`resetMap()` / `buildMap()`** — on **Run**: teleport to starts, spawn proxies. On **Stop** or **natural run end** (success/fail/stuck/timeout): ``TrainingLabController/finalizeTransitRun`` runs ``onTransitRunWillResetMap`` + default ``[Metrics]`` capture, then hold/disarm, ``applySimState`` to start poses, remove proxies. Proxies for ``.trainingRoster`` are lab-managed only (no auto-spawn on SITL add).
- [x] **PX4 pose in Gazebo** — SITL home (`PX4_HOME_*` / ArduPilot `-l`) + Gazebo placement hint from **start formation slot** ENU via ``TrainingLabSitlSpawnAlignment`` / ``spawnAlignmentForPendingEntry`` (roster add/replace + teaching shell); map geodetic origin from manifest ``defaultSpawn``.
- [x] **Start at formation slots (v1)** — ``buildMap`` / ``resetMap`` + post-spawn ``positionVehicleAtStartSlot`` use start-zone slot ENU; teach layout no longer overrides slot pose when zones are placed. **Geodetic shim (v1):** ``TrainingEnvironmentGeodesy/mapSessionOrigin`` anchors lat/lon at manifest ``defaultSpawn`` for map session / run goals / formation SITL seeds.
- [x] **Run Drawers** — Map drawer omitted while a transit run is active; **Stop** before changing map (⌘1 blocked with toast).

**Deferred to end of v1:** **Teaching loop** — see **End of v1** (needs roadtest-derived metrics from sim truth, not map geodesic alone).

---

## Phase 4e - v1 vehicle meshes

- [ ] **Heading Arrow** — Add a flat direction arrow on top of vehicle mesh to show heading.
- [ ] **Telemetry Pin** — Add a floating pin above vehicle mesh (that moves with it) with a traffic light colour to represent vehicle connection status (vehicle 2 word coloured status concept)

## Phase 4c — v1 squad transit (start zone → end zone, no waypoints)

Mission-shaped **Training run**: stage → execute → succeed/fail → stop/analyse. Replaces the interim split where **Run** either starts open-loop **teach** or open-ended **formation follow** without end-zone goals.

- [x] **Training run orchestrator (v1)** — ``TrainingLabRunOrchestrator`` + **Run** / **Stop** wiring; phase machine; **Training** rail + logs; parallel **open-loop** transit drive (``TrainingLabTransitMotion`` + training control segments) + end-slot monitor + timeout. Full Nav2 ``navigate_to_pose`` remains Phase 7.
- [x] **End zone as goal (v1)** — ``TrainingLabRunGoalResolution`` builds per-primary start→end ``TrainingTaskLayout`` from zone formation slots.
- [x] **Structured outcomes (v1)** — ``TrainingRunModels`` + squad rollup on complete/stop/timeout; staging/plan failures typed.
- [x] **Multi-squad v1 policy (locked)** — **all** linked squads transit on one **Run**, each brain-driven; **learning** squad = teach/eval target; non-learning squads = known-simple brain tasks.
- [x] **UGV execution strategy (locked for v1)** — primary-only roster: **Nav2 per vehicle → end slot**. Wingmen: deferred hybrid (end slot + formation while moving) — do not wire MRE-style follow-only for Training transit v1.
- [x] **Safety / abort** — map floor bounds + along-path stuck detection (``TrainingLabRunSafetyMonitor``); operator **Stop** tears down drive + map session (existing). Stuck timer **not** paused for waypoint dwell until Phase 4d.

**Cross-links:** ``TrainingLabFormationSlotStaging`` (pre-Run staging only today); ``TrainingSkillScorer`` (single-goal seed for validation); ``FormationsPlaygroundView/startSession()`` (current Run entry — to be refactored).

---

## End of v1 (after critical path)

Ship only after **v1 critical path** steps 1–5 are roadtested and failure modes are understood.

- [ ] **Teaching loop** — metrics from sim truth (``TrainingSkillScorer`` / promotion); skill teach remains **single-vehicle roster** / squad-of-one. Define metrics from roadtest logs, not upfront guesswork.
- [ ] **Training templates (Phase 4b)** — save/load lab setup (`TrainingTemplateStore` TBD); UI deferred.
- [ ] **Mission-like waypoints (Phase 4d)** — ordered stops, dwell, formation jobs; stuck timer pause during dwell.

---

## Phase 4d — Future: mission-like waypoints (spec — implement in End of v1)

- [ ] Ordered **waypoints** per squad (or shared route across squads).
- [ ] Per-waypoint **jobs**: formation kind, spacing, **group heading vs per-vehicle slot heading**, dwell time, task hooks.
- [ ] **Waypoint delay / dwell vs stuck auto-fail** — while a squad is executing a per-waypoint **delay** (hold at waypoint), **pause** ``TrainingLabRunSafetyMonitor`` along-path stuck timing (`stuckNoProgressWindowS` / `stagnantSince`); do not auto-fail for “no progress” until dwell finishes. Revisit whether the whole-run monitor timeout (``TrainingLabRunOrchestrator`` `runTimeoutS`) should pause for the same dwell window.
- [ ] Schema / template hooks (extends Phase 4b **Future fields**).

---

## Phase 4b — Training templates (save & re-run — spec — implement in End of v1)

Let operators **save the current lab setup as a named template** and **load it later** to re-run the same training without binding a map to a single skill or scenario.

**Persist (v1 shape — extend as the lab gains fields):**

| Slice | Contents |
| --- | --- |
| **Map reference** | `TrainingEnvironmentManifest` id (or stable catalogue key) — **reference only**. |
| **Vehicle roster** | Squads (ids/labels), entries (class, tier, roles), per-squad formation policy (start/end formation + spacing). |
| **Training requirements** | Task kind (app-wide on ``TrainingPanelController`` — **Training** rail not shipped), forbidden axes, teaching options, brain-export prefs. |
| **Future fields** | Waypoints (Phase 4d), geofences, episode limits, transit run prefs, etc. |

**Product rules:**

- Saving a template does **not** claim exclusive ownership of a map.
- Loading restores lab state; operator may change map or vehicles before **Run**.
- Templates live in Training app storage (`TrainingTemplateStore` TBD).

**UI (deferred):** Save / Load / Duplicate / Delete from Training rail or sub-bar overflow; confirm on delete (`GuardianConfirmDanger`).

---

## Phase 5 — Squads in one world (formation slots + map session)

- [x] **Environment catalogue + zone formation slots** — start/end zones; per-squad anchors and `TrainingLabFormationSlotGeometry`.
- [x] **Multi-vehicle `.run` map session** — `buildMap` / `resetMap` from zone layouts (or staggered manifest fallback); Gazebo proxies per vehicle.
- [x] **Embedded 3D viewport** — `guardianFormationSlots` + `GazeboWebViewportFormationSlotsBridge`.
- [x] **Leave-tab contract** — ``TrainingLabController/leaveLab`` on panel `onDisappear`: active run → ``TrainingLabRunOrchestrator/stop``; else ``resetMap`` + formation session stop; all roster fleet streams stopped; roster + map selection persisted; Gazebo **run** world stays warm (no ``stopTrainingGazeboRunWorld`` on tab leave).

### Squad formation slots in start/end zones

- [x] **Start zone** — squad start group inside map start zone (center, radius, shape).
- [x] **End zone** — squad end group inside map end zone.
- [x] **Drag + rotate** — footprint rings, drag primary when squad selected, snap on invalid drop; gold **diamond** rim handle; `mapSelectedSquadID` for edit highlight.
- [x] **Policy-driven slot layout** — squad settings (formation/spacing) + roster refresh; **Run** staging rejects overlap / OOB (`TrainingLabFormationSlotStaging`).
- [x] **Squad caps** — 3 squads, 6 vehicles per squad (`TrainingLabRosterLimits`).
- [x] **Operational spacing** — `MissionSquadFormationFootprintSpacing` for live vehicle clearance.

**Cross-links:** ``TrainingLabSquadSettingsDrawerContent``; ``TrainingLabMapSessionLifecycle``; ``MissionSquadFormationGeometry`` (MRE + lab).

---

## Phase 6 — Multiple connected squads (after v1 critical path)

- [x] **Squad identity + learning picker** — NATO callsigns, colours, sub-bar **Learning** when multiple squads have sims.
- [ ] **World strategy** — implement **one `.run` world, all squads active** (locked in product model); collision / scale warnings remain.
- [ ] **Collision groups** — inter-squad / proxy collision in Gazebo.
- [ ] **Scale warnings** — large maps (e.g. 4 km²), terrain, water features.

**Note:** Multi-squad transit policy is shipped (Phase 4c); harden **after** single-vehicle roadtest lane passes.

---

## Phase 3c — Procedural terrain (World Builder)

- [ ] **Tracker:** `ToDo/GazeboTerrainToDo.md` — heightmaps, `sceneType` + `terrainParams`, generator, `TerrainQuery`, Gazebo include.

---

## Phase 7 — Motion, Nav2, Gazebo sync (UGV v1 — follow **v1 critical path** order)

### Now (roadtest lane)

- [ ] **1 — Motion proof** — confirm **Run** changes SITL pose in sim (operator roadtest). **Wiring shipped:** arm-before-drive (``FleetLinkService/ensureArmedForTransitDrive``), open-loop segments, start/end hub pose + horizontal delta in run logs (``TrainingLabTransitMotionProof``).
- [x] **2 — Nav2 plan on Run** — ``TrainingLabRunPathPlanning/resolveAllForRun`` at **Run** start (PX4 sidecar enroll → ``plan_path`` per vehicle); same polyline feeds open-loop drive, stuck monitor, learning-squad map overlay (``applyRunPlannedPath``), and ``[Metrics]`` path source. Operator roadtest: run log should show `route nav2` when fleet stack is ready (else `geodesic_fallback`).
- [x] **3 — Proxy telemetry sync** — ``TrainingLabGazeboProxyTelemetrySync`` (~5 Hz during ``phase == .running``): hub lat/lon/heading → map ENU via ``GazeboService/updateVehicleProxyPose`` / ``setModelPose``. Operator roadtest: proxy tracks SITL in embedded viewport.
- [ ] **4 — Nav2 execute** — ``navigate_to_pose`` (or PX4 Rover setpoint path) replaces or validates open-loop segments for UGV transit to end slot.
- [ ] **5 — Roadtest instrumentation** — run logs: pose samples, path source (nav2 vs geodesic), segment outcomes, planner/sidecar status; use to define End-of-v1 metrics.

**Partially shipped (do not close step 4 yet):** ``ensurePx4Ros2Sidecar`` on transit drive; map debug Nav2 status line; open-loop segment follower. **2026-05-21 fix:** readiness + ``plan_path`` now use Nav2 **``/compute_path_to_pose`` action** (Humble dropped the service) — was stuck on ``starting`` forever.

### Later (post roadtest)

- [ ] **ROS 2 sidecar hardening** — every linked roster vehicle after MAVLink up; Formation / MCR reuse same API (`README_AUTONOMY.md`).
- [ ] **Costmap from world** — static obstacles / terrain from manifest + Gazebo (large maps, rivers, lakes).
- [ ] **Geodetic bridge** — ENU zone coords ↔ WGS84 for Nav2 / PX4 (see open questions).
- [ ] Formation-aware goals on slopes; health chips (slope export — `ToDo/GazeboTerrainToDo.md` Phase 7).

---

## Phase 8 — Polish

- [ ] Remove Leaflet when 3D default; Theme catalog; manual smoke; trim `ToDo/TODO.md`.
- [ ] **Portable GazeboRuntime** — relocatable bundle (no Homebrew on operator machine).

---

## Open questions (revisit for transit run + Nav2)

| Topic | Notes |
| --- | --- |
| Viewport tech | Metal vs `WKWebView` / gz-web |
| Geodetic bridge | ENU vs WGS84 for Nav2 / PX4 handoff |
| UAV worlds | v1 UGV-focused |
| Physics rate | real-time vs accelerated |
| Transit vs teach | Same **Run** button evolves to transit; teach trials may stay a sub-mode for squad-of-one skill promotion |

---

## References

| Area | Path |
| --- | --- |
| Training lab UI | `FormationsPlaygroundView.swift` (`TrainingLabPanelView`), `TrainingLabController.swift` |
| Roster / squads | `TrainingLabRosterController.swift`, `TrainingLabRosterModels.swift`, `TrainingLabRosterStore.swift` |
| Map session | `TrainingLabMapSessionLifecycle.swift`, `TrainingLabFormationSlotStaging.swift` |
| Transit drive | `TrainingLabTransitMotion.swift`, `TrainingLabTransitMotionProof.swift`, `TrainingLabRunOrchestrator.swift` |
| Proxy pose API | `GazeboEntityFactoryClient.swift` (`setModelPose`); `TrainingLabGazeboProxyTelemetrySync.swift` |
| World Builder | `WorldBuilderView.swift`, `WorldBuilderController.swift` |
| Environments | `TrainingEnvironmentCatalogue.swift` |
| Gazebo | `GazeboService.swift`, `GazeboSessionPurpose.swift` |
| Nav2 / ROS | `README_AUTONOMY.md`, `FleetLinkService.swift`, `FleetNav2StackRunner` |

---

## When this file is empty

Migrate locks to `README_FULL.md`, delete this file.

# Training + Formation — Gazebo 3D simulation

Goal: replace the **open-field Leaflet** training / formation playgrounds with a **bundled 3D physics simulator** (target: **Gazebo**, or a maintained equivalent such as **Gazebo Harmonic / Ignition Gazebo**) so operators can run skill training and formation rehearsal in **authored worlds** — obstacles, start/end poses, and **non-flat terrain** (UGV slope practice, realistic contact).

**Today:** **Training** (`TrainingPanelView` / `TrainingPanelController`) and **Formation** (`FormationsPlaygroundView` / `FormationsPlaygroundController`) use **SITL** (`SitlService`) for vehicles and **Leaflet** (`GuardianMapView` / `OSMMapView`) for map chrome, target-slot editing, and squad layout preview. Worlds are effectively flat WGS84 coordinates + spawn defaults — no mesh terrain, no static obstacles in the sim.

**Later:** Mission Control running maps and Live Drive may stay on Leaflet / Cesium (see `CesiumJSMapIntegrationReadMe.md`); this tracker is **Training + Formation simulate tabs only** unless product expands scope.

**Cross-links:** `TODO.md` → **Training**; `AppTrainingMissionSplitToDo.md` (Training.app vs Mission.app, **Guardian Brain Pack** export); `README_FULL.md` → **Live Leaflet map** (what we are *not* replacing in v1); `Sources/GuardianHQ/Resources/Ros2VehicleBridge/README_AUTONOMY.md` (Nav2 / PX4 rover sidecar); `SquadFollow&Formation.md` (formation motion, post-Gazebo convoy).

---

## Phase 0 — Product lock + platform choice

- [ ] **Pick simulator stack** — Gazebo Harmonic (or agreed successor) on macOS arm64; document fallback if Apple Silicon gaps block classic Gazebo (e.g. containerized sim, headless + streamed viewport).
- [ ] **PX4 + UGV alignment** — confirm rover models, plugins, and SIH vs full physics path match current Training locks (`SimulationSpawnPolicy` → PX4 for UGV; `TrainingVehicleClass` UGV-W / UGV-T).
- [ ] **ROS 2 bridge contract** — how Guardian’s existing `guardian_ros2_vehicle_bridge` + Nav2 receives **occupancy / elevation** from the 3D world (costmap source, frame ids, update rate).
- [ ] **Scope v1 surfaces** — Training **Vehicle** tab first; Formation **Formation** tab second; Leaflet removed from those panels only when 3D viewport is shippable.
- [ ] **Licensing + redistribution** — verify bundling Gazebo (+ deps) inside `Guardian HQ.app` / SwiftPM resources (same discipline as `Px4SitlBundle`, `ArduPilotSitl`, `Ros2Runtime`).

---

## Phase 1 — Bundle Gazebo (or equivalent) with the app

- [ ] **Runtime layout** — `Sources/GuardianHQ/Resources/GazeboRuntime/` (or named bundle) with version pin, fetch script (`scripts/fetch_gazebo_runtime.sh` / `make gazebo-runtime`), and `.meta` stamp like other sim deps.
- [ ] **Process launcher** — `GazeboLaunchRecipe` / `GazeboService` mirroring `SitlLaunchRecipe` / `SitlService`: spawn world, manage child PIDs, ports, logs, orphan cleanup on cold launch (`GuardianSitlOrphanBlitz` pattern).
- [ ] **Simulate gate** — respect top-bar **Simulate** + existing fleet link registration; Gazebo worlds only start when simulate is on.
- [ ] **Resource budgets** — document minimum RAM/CPU; cap concurrent worlds / vehicles; env var for max concurrent Gazebo instances (parallel `GUARDIAN_MISSION_RUN_SIM_CLEANUP_MAX_CONCURRENT` style).
- [ ] **Packaging** — `scripts/package-macos-app.sh` copies runtime into `.app`; README subsection for “first run downloads / builds Gazebo bundle”.
- [ ] **Failure surfaces** — operator-visible errors (missing runtime, world load fail, version skew) — no “future build” copy.

---

## Phase 2 — Training environment catalog (stored defaults)

- [ ] **Environment model** — `TrainingEnvironment` (or `GazeboTrainingWorld`) `Codable`: id, display name, description, world file reference, default spawn, default goal, tags (UGV, indoor, slope, etc.).
- [ ] **On-disk library** — bundled defaults under `Resources/TrainingEnvironments/` (`.sdf` / `.world` + metadata JSON); operator-added worlds in Application Support.
- [ ] **Catalogue UI** — picker in Training Vehicle panel (replace / augment free-map target-slot-only flow): choose environment before spawn.
- [ ] **Import / export** — zip or folder import for custom environments; validate schema on load.
- [ ] **Versioning** — environment format version field; reject unknown versions with clear message.
- [ ] **Persistence** — last-used environment per Training task kind; optional per-vehicle-class defaults.

---

## Phase 3 — Environment authoring (obstacles, start, goal, terrain)

- [ ] **Authoring spec** — define what v1 must encode: static meshes, boxes, cylinders, georeferenced origin, **start pose(s)**, **goal region** (point / polygon / slot), optional lane markers.
- [ ] **In-app editor (minimal v1)** — place/move start & goal; add primitive obstacles; save to Application Support catalogue entry.
- [ ] **Terrain** — heightmap or DEM tile import (bounded region); visualise slope in viewport; export collision mesh for Gazebo physics (UGV pitch/roll on grades).
- [ ] **Validation** — spawn point on navigable surface; goal reachable; no obstacles intersecting spawn; max world size / entity count caps.
- [ ] **Preview mode** — fly-through camera without sim running (load world only).
- [ ] **Map sync (optional v1)** — export 2D footprint / occupancy slice for Nav2; if deferred, capture in `NEXTVERSION.md` with explicit blocker.

---

## Phase 4 — Training: single vehicle in Gazebo

- [ ] **Replace Leaflet column** in `TrainingPanelView` with embedded 3D viewport (native or `WKWebView` + gz-web / agreed renderer).
- [ ] **Spawn pipeline** — `TrainingPanelController.spawnTrainingSim` launches Gazebo world + PX4 SITL (or gz-sim bridge) with poses from selected environment; retain `SitlSpawnOwner.trainingVehicle`.
- [ ] **Target slot / task layout** — bind `TrainingTaskLayout` start/goal to environment anchors (not only lat/lon on flat map); `TrainingTargetSlotStore` stores environment-local or georeferenced poses consistently.
- [ ] **Teaching loop** — open-loop trials and skill promotion unchanged logically; pose error metrics use sim ground truth from Gazebo / MAVLink, not Leaflet drag handles.
- [ ] **Operator controls** — retry/replace sim card; preflight + link wait unchanged; logs include Gazebo stdout path.
- [ ] **Regression tests** — pure-Swift: environment JSON round-trip, catalogue registration, spawn recipe argument building (no full Gazebo in CI).

---

## Phase 5 — Formation: single squad in one world

- [ ] **Formation environment** — reuse catalogue; squad spawn grid / offsets relative to environment start frame (`FormationsPlaygroundController` staggered spawn).
- [ ] **Multi-vehicle spawn** — N vehicles in one Gazebo world; unique MAVLink ports / ROS namespaces per slot (`FormationsPlaygroundSlotState`).
- [ ] **3D viewport** — replace Formation map column; show all squad markers + formation slot group edit in world space.
- [ ] **Apply formation** — streamed OFFBOARD/GUIDED setpoints still via fleet link; geofence / squad utilities consume world-frame positions.
- [ ] **Leave tab behaviour** — sims persist in Garage (`SitlService`); only streams stop (current contract).

---

## Phase 6 — Multiple connected squads

- [ ] **Squad identity model** — `FormationSquadID` (or reuse mission squad ids) for 2+ independent squads in one training session.
- [ ] **World strategies** — (a) one large world, multiple spawn groups, or (b) linked sub-worlds / instances with shared origin — pick one v1 approach and document.
- [ ] **UI** — squad switcher; per-squad vehicle class + formation shape; colour / label in viewport.
- [ ] **Inter-squad constraints** — optional geofence between squads; collision groups in SDF so squads do not physics-collide unless intended.
- [ ] **Scale limits** — max squads × vehicles per machine; operator warning before spawn.

---

## Phase 7 — Nav2, costmaps, and autonomy integration

- [ ] **Costmap from Gazebo** — occupancy + elevation layer generation (static + optional dynamic obstacles); publish on per-vehicle namespace.
- [ ] **Planner goals** — Training task goals → Nav2 action goals in world frame; success criteria aligned with `TrainingTaskKind`.
- [ ] **Formation path** — convoy setpoints respect terrain height (future tie-in `SquadFollow&Formation.md` § trail / router).
- [ ] **Health in UI** — Gazebo running, world loaded, bridge alive chips on sim cards (Theme tokens).

---

## Phase 8 — Polish, migration, and docs

- [ ] **Remove Leaflet** from Training + Formation panels when 3D path is default; keep Leaflet utilities for MCS / Missions / Settings.
- [ ] **Theme catalog** — 3D viewport + environment editor blocks in Theme plugin.
- [ ] **README_FULL.md** — subsection: Gazebo training runtime, environment catalogue paths, spawn ownership, Nav2 data flow.
- [ ] **AGENTS.md** — pointer for agents editing Training / Formation simulate UI.
- [ ] **Manual smoke checklist** — single UGV slope course, obstacle weave, 3-vehicle formation, two-squad spawn, teardown on Simulate off.
- [ ] **Retire duplicate TODO** — when phases 0–4 ship, trim `TODO.md` **Training** Gazebo bullet to “in progress / see tracker” or remove per todo hygiene.

---

## Open questions (resolve in Phase 0)

| Topic | Options / notes |
| --- | --- |
| Viewport tech | Native Metal scene vs `WKWebView` (gz-web, three.js scene server) vs stream-only |
| Georeferencing | Local ENU origin per environment vs global WGS84 (affects `SimSpawnDefaults` alignment) |
| UAV in Gazebo | v1 UGV-only worlds vs multi-class environments (Training still UGV-locked product-wise) |
| Physics rate | Real-time vs accelerated sim for long training batches |
| Cloud worlds | out of scope v1; catalogue is local + bundled |

---

## References

| Area | Path |
| --- | --- |
| Training UI | `Sources/GuardianHQ/Systems/Formations/Views/FormationsPlaygroundView.swift` (`TrainingPanelView`) |
| Training controller | `Sources/GuardianHQ/Systems/Training/TrainingPanelController.swift` |
| Formation controller | `Sources/GuardianHQ/Systems/Formations/FormationsPlaygroundController.swift` |
| Task / layout models | `Sources/GuardianHQ/Systems/Utilities/Training/TrainingTaskModels.swift` |
| SITL spawn (today) | `Sources/GuardianHQ/Infrastructure/Simulation/SitlService.swift`, `SitlLaunchRecipe.swift` |
| Leaflet map stack | `Sources/GuardianHQ/General/Utilities/Templates/Map/GuardianMapView.swift`, `OSMMapView.swift` |
| ROS / Nav2 | `Sources/GuardianHQ/Resources/Ros2VehicleBridge/README_AUTONOMY.md` |
| PX4 bundle pattern | `Resources/Px4SitlBundle/`, `README_FULL.md` → built-in SITL |
| 3D map (separate track) | `CesiumJSMapIntegrationReadMe.md` |

---

## When this file is empty

Migrate locked architecture (runtime paths, environment JSON schema, spawn ownership, frame conventions) to `README_FULL.md`, delete this file, and leave at most a one-line pointer in `TODO.md` if optional work remains.

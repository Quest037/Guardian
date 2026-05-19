# Training app + Mission app split — autonomy brain export

Goal: ship **two macOS apps from one codebase** — **Guardian Training** (lab) and **Guardian Mission** (operations) — so Training can bundle **Gazebo**, heavy sim assets, and skill/formation rehearsal without bloating the field app. Training **promotes and exports versioned autonomy brains**; Mission **imports** a brain and **MRE** uses it as the **default OFFBOARD control policy** for vehicles, with **Nav2** (UGV/USV) and **Aerostack2** (UAV) handling squad-level motion in **Mission Control Running (MC-R)**.

**Today:** One executable (`GuardianHQ`) with Training + Formation simulate tabs, Mission Control, Missions, Live Drive, Garage. Training writes **`TrainedVehicleSkill`** (open-loop **`TrainingControlSegment`** chains) to Application Support via **`TrainingSkillStore`** — **not** consumed by MRE. MRE (`MissionRunEnvironment`) orchestrates runs via fleet recipes, observers, and streamed setpoints; ROS sidecar stubs document Nav2 / Aerostack2 routing (`README_AUTONOMY.md`) but **no** training-brain dispatch yet.

**Related trackers:** `TrainingGazeboSimulationToDo.md` (3D worlds in Training app); `CesiumJSMapIntegrationReadMe.md` (MC-R / Live Drive maps stay ops-focused); `TODO.md` → **Training**, **Vehicles System** (autonomy).

---

## Product lock (read first)

- [ ] **Two apps, one repo** — SwiftPM: shared **`GuardianCore`** library + **`GuardianTraining`** + **`GuardianMission`** executables (optional third **`GuardianHQ`** “full” target until cutover).
- [ ] **Brain = export artefact, not “copy MRE”** — Mission does **not** embed `MissionRunEnvironment`; it imports a **pack file** (see **Guardian Brain Pack** below) and MRE resolves **which pack version** is active per run / task / vehicle class.
- [ ] **Default vehicle motion** — promoted training output drives **OFFBOARD** execution (segment stream and/or planner goals derived from the pack); MAVSDK remains arm/mode/telemetry; ROS planners are **squad / class** backends.
- [ ] **Squad management in MC-R** — multi-vehicle coordination uses **Nav2** (ground/surface) and **Aerostack2** (aerial) under MRE dispatch, informed by brain metadata (formation offsets, stagger, forbidden axes, environment frame) — not a parallel ad-hoc stream-only path for production runs.
- [ ] **Operator versioning** — operators explicitly choose a **brain version** (or “pinned default”) before / during mission setup; audit which version ran on each mission export.

---

## Guardian Brain Pack (export file concept)

Portable, **versioned** file (or signed bundle) Training writes and Mission imports. Working name: **Guardian Brain Pack** (`.guardianbrain` zip or single JSON + sidecar files).

### Pack contents (v1 target)

| Section | Purpose |
| --- | --- |
| **`manifest`** | `format_version`, `brain_id` (UUID), `brain_version` (semver or monotonic int), `display_name`, `created_at`, `training_app_build`, `vehicle_classes[]`, `task_kinds[]`, optional `gazebo_environment_id` |
| **`skill`** | Evolved from `TrainedVehicleSkill`: `segments[]`, `layout`, `score`, `summary` |
| **`planner_hints`** | Optional Nav2 / Aerostack2 param overlays, costmap footprint refs, max speed, frame id |
| **`squad_profile`** | Optional formation defaults for MC-R (slot spacing, convoy offsets, class mix) — Formation lab contributes here |
| **`provenance`** | Training trial index, sim platform (PX4), world hash, promotion operator (future), checksum |

### Versioning rules

- [ ] **`brain_id`** — stable identity across iterations (“Reverse parking — UGV-W”).
- [ ] **`brain_version`** — monotonic; Training **Export** always creates a new version; Mission lists all imported versions for that `brain_id`.
- [ ] **`format_version`** — schema gate; Mission rejects unknown major versions with operator-readable errors.
- [ ] **Compatibility matrix** — document which Mission app builds accept which `format_version` (in pack manifest + README).

### Storage (Mission app)

- [ ] **Import location** — `Application Support/Guardian/brains/<brain_id>/<brain_version>/` (manifest + files).
- [ ] **Catalogue UI** — list brains, versions, vehicle/task tags, promotion date; **pin default** per vehicle class + task kind.
- [ ] **Run binding** — `MissionRunEnvironment` (or envelope) records `activeBrainVersionIDs` per task / squad / assignment policy slot.

---

## Phase 0 — Autonomy pack schema + Training export (monolith-friendly)

Ship schema and export **before** splitting apps so Mission can integrate against real files while still one target.

- [ ] **Define `GuardianBrainPack` Codable** — Swift models in shared module (evolve `TrainedVehicleSkill`, do not break `TrainingSkillStore` until migration).
- [ ] **Training: Export brain** — action on promoted skill (and Formation export when ready): write `.guardianbrain` to disk + “Reveal in Finder”.
- [ ] **Training: New version** — re-export bumps `brain_version`; same `brain_id` if operator confirms “new revision of same brain”.
- [ ] **Mission: Import brain** — file picker + drag-drop; validate checksum / `format_version`; show in catalogue.
- [ ] **Tests** — round-trip encode/decode, version rejection, duplicate import idempotency (`XCTest` on pure Swift).

---

## Phase 1 — SwiftPM split (single codebase)

- [ ] **`GuardianCore` target** — Fleet, MAVSDK, simulation spawn, Utilities (training models, segment stream), design system, logging, ROS bridge coordinator interfaces, brain pack models.
- [ ] **`GuardianTraining` executable** — `TrainingPanelView`, Formation lab, Gazebo runtime resources, skill teacher, export UI; sidebar: Training-focused (no Missions / MC-R / Live Drive).
- [ ] **`GuardianMission` executable** — Dashboard, Missions, Mission Control, Live Drive, Garage, Settings, Plugins; brain import catalogue; **no** Gazebo bundle.
- [ ] **Resources per target** — `Package.swift` copies `GazeboRuntime` / training worlds only into Training; keep `Px4SitlBundle`, `Ros2Runtime`, `mavsdk_server` in both or Mission-only per sim policy.
- [ ] **Shared tests** — `GuardianCoreTests`; app targets thin smoke only if needed.
- [ ] **Packaging** — `scripts/package-macos-app.sh` variants or flags: `Guardian Training.app`, `Guardian Mission.app` (distinct bundle ids).
- [ ] **AGENTS.md + README** — which target to build for which workstream.

---

## Phase 2 — Training app (lab product)

- [ ] **Gazebo + environments** — follow `TrainingGazeboSimulationToDo.md` inside Training target only.
- [ ] **Promote → export loop** — every successful promotion offers export; optional auto-export on promote (setting).
- [ ] **Formation → squad_profile** — export multi-vehicle rehearsal metadata for MC-R squad dispatch (spacing, shapes) as brain pack section.
- [ ] **Nav2 tuning in lab** — when ROS overlay runs in Training, capture **planner_hints** from tuned runs into the pack (not only open-loop segments).
- [ ] **No MRE / no mission templates** — Training does not load `MissionStore` or start `MissionRunEnvironment`; SIM vehicles use same `FleetLinkService` patterns as today.

---

## Phase 3 — Mission app (ops product)

- [ ] **Brain catalogue screen** — import, list versions, pin defaults, delete old versions (confirm).
- [ ] **Mission / MCS binding** — per mission template or per-run envelope: choose brain version per task kind + vehicle class (dropdown from catalogue).
- [ ] **MC-R indicator** — show active brain name + version on task triage / roster (read-only during run unless policy allows mid-run switch — product lock).
- [ ] **Mission export / logs** — include `brain_id`, `brain_version`, `format_version` in structured run export and Paladin-facing templates.
- [ ] **Simulate without Training tab** — Garage + SITL unchanged; no Gazebo dependency.

---

## Phase 4 — MRE: brain as default OFFBOARD policy

- [ ] **Dispatch resolver** — when MRE issues vehicle motion (between-cycles, task legs, recovery — per existing recipe graph), resolve **active brain pack** → execution strategy:
  - [ ] **Segment path** — `FleetLinkService` training-style stream (`executeTrainingSegment` or renamed **brain segment executor**) for pack `skill.segments`.
  - [ ] **Planner path** — translate pack goals / layout into Nav2 `navigate_to_pose` or Aerostack2 mission items when `planner_hints` present.
- [ ] **OFFBOARD default** — if a vehicle has a bound brain version and policy allows autonomy, prefer brain executor over legacy one-off setpoints unless operator Live Drive / recipe lock overrides (`liveDriveControlSessionVehicleID`, recipe ownership gates).
- [ ] **Fallback** — explicit MRE log + operator prompt when brain missing, import corrupt, or planner unavailable (no silent SIH-only drift).
- [ ] **Correlation** — `MissionRunRecipeOutcomeCorrelation` / audit `source` strings reference `brain_id` + `brain_version`.
- [ ] **Tests** — resolver unit tests with fixture packs; no full Gazebo in CI.

---

## Phase 5 — MC-R squad management (Nav2 + Aerostack2)

- [ ] **Class-aware squad coordinator** — MRE squad dispatch selects **Nav2** for UGV/USV squads and **Aerostack2** for UAV squads (`GuardianAutonomyPlannerRouting`); mixed-class squads: product rule (split squads vs degraded mode).
- [ ] **Brain-informed formation** — apply `squad_profile` from pack (offsets, trail, shape) through existing wingman / convoy subsystems where compatible (`MissionRunSquadFollowSubsystem`, `SquadFollow&Formation.md`).
- [ ] **Single-world sim in Mission** — Mission MC-R continues SITL + Leaflet/Cesium; does **not** require Gazebo; brains trained in Gazebo must declare **transfer** assumptions (flat world vs terrain) in manifest.
- [ ] **ROS sidecar** — extend `ensurePx4Ros2Sidecar` + bridge for MCR vehicles per `README_AUTONOMY.md` rollout table; brain pack supplies namespace / planner param overlays.
- [ ] **Operator prompts** — squad planner failures surface MC-R prompts (retry formation, park squad) with brain version in detail.

---

## Phase 6 — Cutover, deprecation, hygiene

- [ ] **Migrate `TrainingSkillStore`** — optional import legacy JSON into brain catalogue on first Mission launch.
- [ ] **Retire Training tab from monolith** — when Training.app ships, remove `.training` from `AppSection` in Mission app (or hide behind dev flag).
- [ ] **Update `TODO.md`** — point Training / autonomy bullets here; trim duplicate prose when phases complete (todo hygiene).
- [ ] **README_FULL.md** — subsection: two-app model, brain pack paths, MRE default OFFBOARD policy, version pinning.
- [ ] **Manual smoke** — Training: promote + export v1/v2; Mission: import both, pin v2, run MC-R SIM with OFFBOARD brain; squad Nav2 formation on 2× UGV.

---

## Dependencies between trackers

```
Phase 0 (pack schema + export/import in monolith)
    ↓
Phase 1 (SwiftPM split)     Phase 2 (Training app + Gazebo)  ← TrainingGazeboSimulationToDo.md
    ↓
Phase 3 (Mission catalogue)
    ↓
Phase 4 (MRE OFFBOARD brain)  →  Phase 5 (Nav2 / Aerostack2 squads)
    ↓
Phase 6 (cutover)
```

---

## Open questions

| Topic | Notes |
| --- | --- |
| Pack signing | Trust model for imported brains (org signature vs unsigned lab) |
| Mid-run brain switch | Allowed in MCS only, never MC-R, or never |
| One brain per task vs per vehicle | MCS UI implications |
| Aerostack2 maturity | UAV brain may be segment-only until AS2 execution ships |
| Paladin | Reads brain version from run envelope for “learn” backlog (`TODO.md` MRE Learn) |

---

## References

| Area | Path |
| --- | --- |
| Training skill model | `Sources/GuardianHQ/Systems/Utilities/Training/TrainingTaskModels.swift` (`TrainedVehicleSkill`) |
| Skill persistence | `Sources/GuardianHQ/Systems/Utilities/Training/TrainingSkillStore.swift` |
| Segment execution | `Sources/GuardianHQ/Systems/Fleet/Services/TrainingControlStream.swift`, `FleetLinkService.executeTrainingSegment` |
| MRE | `Sources/GuardianHQ/Systems/MissionControl/` (`MissionRunEnvironment`, recipe subsystems) |
| Planner routing | `Sources/GuardianHQ/Systems/Utilities/Fleet/GuardianAutonomyPlannerRouting.swift`, `Resources/Ros2VehicleBridge/README_AUTONOMY.md` |
| Squads | `SquadFollow&Formation.md`, `MissionRunSquadFollowSubsystem.swift` |
| Package layout today | `Package.swift` (single `GuardianHQ` target) |
| Gazebo in Training | `TrainingGazeboSimulationToDo.md` |

---

## When this file is empty

Migrate locked decisions (pack schema version, bundle ids, MRE resolver rules, default brain pinning) to `README_FULL.md`, delete this file, and leave a one-line pointer in `TODO.md` only if optional work remains.

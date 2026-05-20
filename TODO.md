# TODO

## Vehicles System

- **Vehicle class sizes (footprint tiers):** `VehicleClassSizeToDo.md` — Phase 1–2 shipped (roster, training, formation, run footprint, brain export); map glyphs, World Builder, ROS bridge open.

## Clean Up
- Replace references to "path" with "task" so that we can get rid of legacy concept.

## Training

- **Brain pack / MRE follow-up (deferred):** `NEXTVERSION.md` → **2026-05-19 — Brain pack & MRE follow-up** (planner-only ROS action client, bounded-task SIM smoke, MCS per-task binding).
- **Gazebo 3D simulation (Training + Formation):** `TrainingGazeboSimulationToDo.md` — bundled Gazebo (or equivalent), training environment catalogue + authoring (obstacles, start/goal, terrain), single-vehicle Training then Formation squads / multi-squad; replaces Leaflet in those simulate tabs when shippable (Training app target).
- **Gazebo embedded viewer — offline mode:** Regenerate `Resources/GazeboWeb/dist/gzweb.bundle.mjs` via `make gzweb-viewer` after gzweb bumps; commit the bundle so packaged apps need no network for the 3D panel.

## App System

- Make clicking non-input UI areas unfocus the currently focused input field (desktop blur-on-background-click behavior).
- **macOS `.app` bundle + UserNotifications:** `AppMacOSBundleUserNotificationsToDo.md` — proper app for TCC / `UNUserNotificationCenter`, local test workflow, optional Xcode app target, delegate + deep link, operator prompt delivery (replaces stub; MC-R background).
- **Internationalization (i18n):** expand localization coverage beyond Paladin log templates to full UI copy, formatting rules, and locale-aware defaults.
- **Extended Display Mode:** - convert app into extended display mode aware to allow user to have different main tabs on different displays (vehicles, logs, missions), and to allow them to do the same for MC-R.

## Performance & diagnostics

- **GuardianHQ CPU with SITL (Xcode process gauges):** With SITL running, Xcode shows the app jumping from ~idle (~4%) to **100%+** CPU (multi-core % is normal above 100%). Explore/debug: distinguish **burst vs sustained** load, **GuardianHQ vs separate sim child processes**, and hot paths (MAVLink / MAVSDK handling, Combine or Rx delivery, **main-thread** work, SwiftUI invalidation, logging). Use Instruments (Time Profiler, Main Thread Checker as needed) and capture what is expected under telemetry volume vs worth optimising.
- Look at splitting MissionControlSetupView into smaller focused files

## Plugins System


## Vehicles System

- **Live vehicle links (MAVSDK + ROS 2):** Implement fleet registration for **live** (non-SITL) vehicles — dedicated MAVSDK session path (not only ``registerSimulatedVehicle`` from ``SitlService``), enroll via ``FleetLinkService/ensurePx4Ros2Sidecar(forVehicleID:)`` when stack is PX4, per-vehicle ROS namespace config, and uXRCE on the airframe (Guardian cannot set params on hardware like SITL spawn). **Phased:** Training sim enrolls first; Formation / MCR / garage / live follow (see ``Sources/GuardianHQ/Resources/Ros2VehicleBridge/README_AUTONOMY.md`` → **ROS sidecar rollout**).
- **Autonomous planning (ROS 2 — Nav2 + Aerostack2):** v1 **planner routing** is in ``guardian_ros2_vehicle_bridge`` (UGV → Nav2, UAV → Aerostack2; see ``README_AUTONOMY.md``). Still to build: live goal injection, costmaps, action clients, Guardian ↔ planner health in UI, and Mission Control / Paladin dispatch hooks.
- **Vehicle Calibration:**
  - Finalise `Sources/GuardianHQ/Systems/Fleet/Models/FleetTelemetryFieldCatalog.swift` — review every group assignment, display label, and formatter; tighten the per-system field lists used by the Vehicle Inspector calibration tab. Anything not yet catalogued falls through to the Telemetry tab "Other" chip.
  - Fine tune `Sources/GuardianHQ/Resources/FleetCalibrationAnchors.json` marker positions against the vehicle class artwork.
  - Soft barometer signal: treat `altitudeAmslM != nil` as "barometer alive" so ArduPilot SITL goes green without `SCALED_PRESSURE` flowing through MAVSDK.
  - Synthesise `healthAllOk` from the AND of the six per-flag health booleans so Estimator clears "Awaiting telemetry" once all `health` events have arrived.
  - RC presence gating: hide the RC marker (or label it "No RC bound") until `rcWasAvailableOnce == true`, so it stops being an amber line in pure-sim runs.
  - **Calibration commands + recipes:** Layer 0 `do.calibrate.*` catalogue + Layer 1
    `recipe.fleet.calibrate.*` / diagnose / error-fix recipes ship in-tree; see
    `README_FULL.md` (Fleet Commands & Recipes) and `CommandsCatalogueDoc.md` §6. **Vehicle
    Inspector wizard + inline escalation** — `NEXTVERSION.md` → **Vehicle Inspector recipe wizard (Stage E)**.
  - Manual Calibration Process (live + sim): **Stage E** wizard in
    `NEXTVERSION.md` Stage E capture (replaces one-off hardcoded flows).
  
- **Vehicle Preflight:**
  - Wire arm / calibration-help UX to catalogue recipes (`recipe.fleet.diagnose.armprobe`,
    `recipe.fleet.errors.fix.*`) — **Stage E** in `NEXTVERSION.md` (recipes already
    registered).
  - **Live-mission recipe / preflight override surfaces.** The default-deny gate now lives in
    `MissionControlStore.runSingleVehiclePreflightProbe` (parameter
    `allowDuringLiveMission: Bool = false`) and the Vehicle Inspector header shows a
    **Recipe locked** pill when a vehicle is bound to a `.running` / `.paused` /
    `.recovery` run (the same signal disables non-`safeInLiveMission` catalogue **Run**
    rows in the Calibration tab). Wire deliberate override paths for the legitimate cases:
    - Reserve drone swap-in — **MC-R pool swap confirm** runs **telemetry-only** snapshot gates (``MissionControlReserveSwapInPreflightGates`` / ``MissionControlPreflightTelemetryGateMode/reserveSwapIn``) then the arm probe with `allowDuringLiveMission: true` and audit `missionControl.preflightProbe.reserveSwapIn` before roster commit; additional swap-time catalogue steps should use distinct `source` strings under `missioncontrol.reserveSwap.*` (see ``MissionRunReserveRecipeRunnerCorrelation``).
    - Drone-recovery flow (vehicle dropped link / went offline mid-mission and we
      need to re-probe arm before sending it back to its task).
    - Plugin authority — Paladin and any future autonomous controller should be able
      to call the probe with `allowDuringLiveMission: true` from their own
      reasoning, with an audit-line attribution.
    Each surface needs a clear confirmation step and an audit entry on the FVM
    recipe-run history (`source` field) so post-mission review can see exactly which
    operator / plugin overrode the gate and why.

- Finish vehicle inspector wizard to be done properly.
  - do the layout, speed, explanation, walk-through and messaging properly.
  - The purpose of the wizard is to make it as easy as possible for the user, not make it difficult.

### Commands Catalogue

Fleet **mission** command atoms and composites still to add: see **FleetCommands** below.
Core fleet vehicle catalogue + recipes: `README_FULL.md` (Fleet Commands & Recipes architecture).

### Controllers System
The controllers system is designed to allow a user to control a linked vehicle with either their keyboard or a connected game controller/joystick. It will also possible to do a hybrid joystick + keyboard.

#### Keyboard

  - **Acceleration/Speed:** 
    - use a qualifier (Shift?) to adjust acceleration speed.

#### Game Controller


#### Joystick


## Utilities System

- **Global Utilities migration:** continue migrating reusable pure helper/derivation functions from MissionControl, LiveDrive, Missions, Settings, and Fleet into the top-level `Utilities.*` namespace (e.g. `Utilities.mission.path.waypoint.*`, `Utilities.fleet.vehicle.*`) so shared logic has one canonical implementation.

## Dashboard System

- Test the "Idle" card when a mission is running. Then test it when 2 missions are running side-by-side. See what it shows/what happens.

## Map System

- **CesiumJS 3D map spike (LiveDrive + MC Running):** evaluate replacing the current Leaflet 2D map in **LiveDrive** and **Mission Control Running** with a CesiumJS-based 3D map mode (camera follow/tracked entity, per-marker context menu parity, route/vehicle overlays, and acceptable telemetry update performance in `WKWebView`). Keep **Settings → default SIM coords** and mission authoring maps on lightweight 2D for now; this spike is for operational views first.

## Live Drive

The Live Drive system allows a user to manually take control of a connected vehicle and send it commands to do things. The user can fly UAVs, drive UGVs etc. This works for both live vehicles and SIMs. This system can be used in freestyle, or can be the way the user takes control of a vehicle in a running mission.


- **LiveDrive map expansion:** Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.
- **Testing:** Test the LiveDrive system with all variants of both stacks to see how they work out.

## Missions

Missions are the templates created by users that involve telling one or more vehicles what, when where and how to do what it needs to do.

- **Mission Templates:**
  - Create pre-defined mission templates that the user can quick start their mission and build from
  - Offer these by default in a modal when user clicks "Add Mission", with the first option being a blank mission.

### Mission Mechanics

### Mission Roster Slots

## Mission Control

Mission Control is the system where mission templates are run by the Paladin system. Paladin in Guardian's mission brain, that reads mission templates and puts them into practive.

Mission Control includes Setup, Running, Recovery Completed as the main four states. It will also have a Simulation mode, where Paladin runs a mission template in a headless environment and reports back on its feasibility.

### Policies

### Pathfinding & geofence avoidance

**Product lock:** Exclusion geofences are **keep-out obstacles** — vehicles must **skirt** them. Inclusion is the operable outer boundary. Do **not** rely on autopilot geofence breach for routing in AUTO or OFFBOARD/GUIDED; FC fences are backup only.

**Observed gap:** Primary AUTO can fly straight legs through exclusions; wingman v1 only holds last valid setpoint (`MissionControlSquadConvoySetpointGeofenceUtilities`). No vehicle→MRE **exclusion approach** reporting or role-specific recovery. See ``SquadFollow&Formation.md`` § v2 **P** (router + **P.1** breach recovery).

- **Guardian 2D router** (Utilities / Mission Control): exclusions non-traversable; stay in inclusion; skirt with clearance; unit tests (hole between start/goal, nested fences, multi-hole). **Canonical checklist:** ``SquadFollow&Formation.md`` § v2 **P**.
- **Mission compile / upload:** Reroute or insert WPs so legs do not intersect exclusions; log detoured vs author path.
- **Runtime setpoint follower:** Shared API for formation streams, park, reposition, policy moves — replace hold-last-valid as sole geofence strategy.
- **Reserve swap / vacancy mission join (decide later):** When a vehicle enters a slot mid-run (reserve swap post-commit, vacancy handoff), decide whether mission start uses **GR + OFFBOARD** to the join point / first leg or keeps direct ``do.mission.upload.start`` / ``do.mission.upload.start.item`` — see ``MissionRunEnvironment+ReserveSwapPostCommitHandoff``, ``MissionRunReserveSwapPostCommitVacancyMissionRecipeSelection``. Defer until launch→WP1 pathfinding is proven in SIM.
- **Exclusion approach → MRE recovery (§ P.1):** Vehicles **report** exclusion approach (Guardian-predicted setpoint/leg violation + optional FC breach/STATUSTEXT); MRE **captures** and runs pathfinding to recover — **primary:** rejoin **mission progress** (routed spine / next cycle leg); **wingman:** rejoin **formation slot** relative to primary (convoy/trail target) while skirting, not independent mission routing. Distinct log keys; SIM smoke for primary stall vs wingman chord-through-hole.
- **FC breach params (optional safety net):** Document/tune stack `FENCE_ACTION` (or equivalent) so FC does not silently fight MRE; Guardian still owns detour geometry — do not rely on FC breach alone for mission recovery.
- **Consumers:** primary AUTO upload; wingman convoy; reserve reposition; between-cycles / end-policy OFFBOARD/GUIDED; **convoy trail** (``SquadFollow&Formation.md`` § v2 **T** — trail motion on top of router, not separate avoidance).
- **SIM smoke:** launch separated from route by exclusion; track outside red zones.
- **v3 road layer** (after v2 open-field router): task domain classification (road vs open-field); OSM snap like mission workspace map; UGV on roads + UAV overwatch on routed track — ``SquadFollow&Formation.md`` § v3 **R**.
- **v3 3D router** (after v2 § P): promote 2D router to **3D** (floor + ceiling); airborne exclusion volumes (e.g. radar keep-outs); full altitude-band enforcement in planner/follower/§ P.1 — ``SquadFollow&Formation.md`` § v3 **3D**.

### Rules of Engagement
- **Rules:**
  - SquadPromote
  - RosterRelease
  - Abort

### Settings


### Mission Control: Simulate Mode (Paladin Only)
- **Mission Control Simulate mode:** add a simulation mode where live vehicle(s) test-run mission paths and feed results back into route refinement via trial-and-error updates. This is run by Paladin, but with operator standing by so that they can take over if a vehicle gets stuck and reroute so that the mission paths can be updated to account for it. This is basically mission testflighting.
- **Failure injection:** - build in intentional failure injections so that MissionControl/Paladin can react.

### Mission Control: Setup
- **Rosters:** 
  - Improve appearance of reserve pool (very tight design currently), maybe use a modal/drawer

### Mission Control: Running

- **MC-R reserve swap picker:** merit-ranked ordering (battery, proximity, link quality, etc.) for floating-pool health cards in the live roster strip; v1 uses ``enumerateReserveSwapCandidates`` order only (see ``MissionRunEnvironment/swapRosterAssignmentWithFloatingReservePoolSlot``).

- **Task Controls (Sidebar):**

- **Map:** 
  - Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.

- **Mission Controls (Sidebar):**

- **Roster:**
  - Functionality to release a vehicle from a roster slot
  - Functionality to select a new vehicle for a roster slot (empty)
  - Functionality to switch a vehicle for a roster slot

- **MissionCleanUp:**
  - Prompts firing after mission has moved into .setup again
    - I understand why this is happening, but it's not ideal

#### Squads
- **Formations (v1 convoy, v2 pathfinding + trail + shapes):**
  - v1: convoy follow shipped — ``SquadFollow&Formation.md`` § v1.
  - v2 **pathfinding** (prerequisite): § v2 **P** + **P.1** + this section **Pathfinding & geofence avoidance**.
  - v2 **convoy trail:** § v2 **T** — trail arc-length + assembly; **depends on pathfinding** for approach and streamed setpoints.
  - v2 **shapes:** chevron, arrowhead, live formation change — § v2 **F** (offsets still pathfound).
- **Squad convoy spacing (authoring):** Per-task or per-squad operator-configurable along-track gap and lateral lane offset (replace locked ``MissionSquadConvoySpacingPolicy`` defaults; UGV v1 SIM uses 3 m astern per ordinal for testing).

### MissionRunEnvironment

#### Executor

#### Commander

#### Logging

#### Planner
- **MissionTask Squad Formations:**
  - v1: convoy + wingman follow pipeline (``SquadFollow&Formation.md`` § v1). Depends on ``MRESquadsToDo.md`` per-squad cycles.
  - v2: **pathfinding** at mission upload + runtime + exclusion approach recovery (``SquadFollow&Formation.md`` § v2 **P**, **P.1**).
  - v2: **convoy trail** — § v2 **T** (blocked on pathfinding).
  - v2: formation shapes + live change — § v2 **F**.

- **MissionTask Squad vehicle promotion:** 
  - build logic for wingman to be promoted to leader, and squad to update accordingly.
  - this is an RoE, that can be autonomous, ask etc.

- **MissionTask Squad vehicle release:** 
  - build logic for planner/operator/assistant to release a vehicle from roster slot completely.
    - Retain the vehicle in new MRE list (voidedVehicles) so that we can keep as map marker (different style), so we can do things like marking it as manually recovered etc.
  - this is an RoE, that can be autonomous, ask etc.
  - Note that user will likely want to swap in a reserve

- **Testing:** - test working with RoE.

#### Scheduling

#### Logging

#### Tasks

  - **Operator prompts:**
    - **User Notifications:**
      - Hook prompts into UserNotifications if user is not watching MCR
    - **MRE Learn:** 
      - MRE instance can learn from operator prompts with operator permission. Such as, "do this from now on", so it can update RoE on the fly.

### Mission Control: Completed
- **Exporting:** 
  - export the mission report for outside app review. (Compact, Default, Full)
  - Include details about individual tasks
  - Include details about individual assignments/vehicles


## Paladin System
Paladin is Guardian's mission running brain. It takes a mission template into mission control: running and executes it according to the specs and rules it is given.

### Paladin Mission Domain

- **Mission Analysis:**
  - Allow Paladin to analyse a mission and find difficulties

### Paladin MC Domain

#### Paladin MissionRunAssistant
- **On-demand vehicle telemetry queries:**
  - add a Paladin-specific active-query path so `MissionRunAssistant` can request immediate values (e.g. battery now, link health now, GPS/attitude now) rather than waiting for passive subscription refresh.
  - Observe task states & vehicle recipes and make sure that stuck vehicles get back on task

### Paladin Fleet Domain

- **Paladin Fleet readiness:**
  - Allow Paladin to auto-calibrate vehicles if possible.

### FleetCommands

- Mission **progress streaming** remains deferred: Layer 0 has no `subscribe` verb yet, so MAVSDK `Mission.subscribeMissionProgress` is not exposed as a catalogue command.

## App Errors

Cross-cutting error system. Foundation only — **Fleet command + recipe layers are
settled**; schedule this when prioritising typed errors across the app. Approach is
**protocol, not envelope**: a core `GuardianError` protocol that each system's existing typed enum
conforms to, so closed taxonomies stay first-class instead of being type-erased into a
wrapper.

- Define `GuardianError` protocol with cross-cutting metadata: `system`, `subsystem`,
  `severity`, `humanDetail`, `stableKindToken`, `cause`, `metadata`.
- Add supporting `GuardianSystemTag` and `GuardianErrorSeverity` enums (severity
  drives toast vs persistent log vs UserNotifications routing).
- Build a kind-token registry so `any GuardianError` round-trips through `Codable`
  (mirrors the `FleetCommandsCatalogueBootstrap` pattern: each conforming type
  registers `(stableKindToken, decoder-closure)` at boot).
- Conform the existing per-system error enums: `FleetLinkError`,
  `FleetLinkParameterError`, `FleetCommandNameError`, `SitlError`,
  `OSMRoutingError`, `GuardianPluginIDError`.
- Add `FleetCommandError: GuardianError` as the typed-error sibling to
  `FleetCommandResponse` (wraps `FleetCommandErrorKind` + detail + elapsed). Layer 1
  recipe escalation events use this as their payload type.
- Switch UI / log / UserNotifications surfaces (`appendVehicleLog`, toast publisher,
  `GuardianBottomPromptCenter`, persistent log) to render `any GuardianError` via a
  single helper. Plain-string paths stay supported during migration.
- Cause-chain rendering (top-level summary + nested causes, expandable in UI).
- Persistence: new logs use the `GuardianError`-shape; legacy plain-string log entries
  stay read-only.

### Bugs
- ArduPilot UGV fails on recipe.fleet.vehicle.do.mission.upload.start (doesn't like mission upload)
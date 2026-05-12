# TODO

## Clean Up
- Replace references to "path" with "task" so that we can get rid of legacy concept.

## App System

- Make clicking non-input UI areas unfocus the currently focused input field (desktop blur-on-background-click behavior).
- **Turn project into real .app:** this allows us to access lots of systems and permissions that our current swift build cannot.
- **UserNotifications:** hook into MacOS user notifications system so that MC-R can keep user updated if app is running in background. Include **MissionRunEnvironment → operator prompts** (see **Operator prompts subsystem** under `### MissionRunEnvironment`) when replacing the prompt stub with delivered notifications.
- **Internationalization (i18n):** expand localization coverage beyond Paladin log templates to full UI copy, formatting rules, and locale-aware defaults.
- **Extended Display Mode:** - convert app into extended display mode aware to allow user to have different main tabs on different displays (vehicles, logs, missions), and to allow them to do the same for MC-R.

## Performance & diagnostics

- **GuardianHQ CPU with SITL (Xcode process gauges):** With SITL running, Xcode shows the app jumping from ~idle (~4%) to **100%+** CPU (multi-core % is normal above 100%). Explore/debug: distinguish **burst vs sustained** load, **GuardianHQ vs separate sim child processes**, and hot paths (MAVLink / MAVSDK handling, Combine or Rx delivery, **main-thread** work, SwiftUI invalidation, logging). Use Instruments (Time Profiler, Main Thread Checker as needed) and capture what is expected under telemetry volume vs worth optimising.

## Plugins System


## Vehicles System

- **Vehicle Calibration:**
  - Finalise `Sources/GuardianHQ/Systems/Fleet/Models/FleetTelemetryFieldCatalog.swift` — review every group assignment, display label, and formatter; tighten the per-system field lists used by the Vehicle Inspector calibration tab. Anything not yet catalogued falls through to the Telemetry tab "Other" chip.
  - Fine tune `Sources/GuardianHQ/Resources/FleetCalibrationAnchors.json` marker positions against the vehicle class artwork.
  - Soft barometer signal: treat `altitudeAmslM != nil` as "barometer alive" so ArduPilot SITL goes green without `SCALED_PRESSURE` flowing through MAVSDK.
  - Synthesise `healthAllOk` from the AND of the six per-flag health booleans so Estimator clears "Awaiting telemetry" once all `health` events have arrived.
  - RC presence gating: hide the RC marker (or label it "No RC bound") until `rcWasAvailableOnce == true`, so it stops being an amber line in pure-sim runs.
  - **Calibration commands + recipes:** Layer 0 `do.calibrate.*` catalogue + Layer 1
    `recipe.fleet.calibrate.*` / diagnose / error-fix recipes ship in-tree; see
    `README.md` (Fleet Commands & Recipes) and `CommandsCatalogueDoc.md` §6. **Vehicle
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
Core fleet vehicle catalogue + recipes: `README.md` (Fleet Commands & Recipes architecture).

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

- Fix reset button going to a fixed zoom (it should use a bbox for everything)

## Live Drive

The Live Drive system allows a user to manually take control of a connected vehicle and send it commands to do things. The user can fly UAVs, drive UGVs etc. This works for both live vehicles and SIMs. This system can be used in freestyle, or can be the way the user takes control of a vehicle in a running mission.

- **LiveDrive takeover of live mission vehicle** Paladin will create a secret key for every vehicle in a mission. User can take over vehicle by inputting key and if Paladin has marked it for takeover. (So if you went cloudbased remote users could achieve this also)
- **LiveDrive takeover of live mission vehicle:** This has been coded, it needs testing properly when Paladin is capable of handing off vehicle to user.
- **LiveDrive map expansion:** Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.
- **LiveDrive UGV/USV/UUV RTL:** At the moment it just drives back in straight line, probably not likely to be able to achieve this. Needs consideration.
- **Testing:** Test the LiveDrive system with all variants of both stacks to see how they work out.

## Missions

Missions are the templates created by users that involve telling one or more vehicles what, when where and how to do what it needs to do.

- **Mission Templates:**
  - Create pre-defined mission templates that the user can quick start their mission and build from
  - Offer these by default in a modal when user clicks "Add Mission", with the first option being a blank mission.

- **Mission image generator:** 
  - Add more preset variations beyond double-chevron.
  - Add a blacklist for hexcode ranges (no black on black)

### Mission Mechanics
- **Mission Task.staggerDelay:** - Add a field (or fields) to control a tasks stagger delay between drone groups when method is staggered. (duration + time style e.g. 30+seconds, 10+mins, 1+hour)
- **Mission Task.geofence:** - Add a geofence limit around a MissionTask to say drones cannot exit it.
- **Mission Task.betweenCycles:** - Add a between cycles param to tell squads what to do between task cycles. These are actions.
  - Loiter, Park, RTL, Charge, GoToStart, GoToPoint etc.


### Mission Roster Slots


## Mission Control

Mission Control is the system where mission templates are run by the Paladin system. Paladin in Guardian's mission brain, that reads mission templates and puts them into practive.

Mission Control includes Setup, Running, Recovery Completed as the main four states. It will also have a Simulation mode, where Paladin runs a mission template in a headless environment and reports back on its feasibility.

### Policies
- **Structure:**
  - Drive policies from **FleetCommandsCatalogue / recipes** where a mission verb maps
    to a catalogue entry (preferential abort/complete + between-cycles dispatch: README
    **Fleet Commands & Recipes** → Mission / MRE policy dispatch).

### Rules of Engagement
- **Rules:**
  - SquadPromote
  - RosterRelease
  - Abort

### Settings
- An object of settings for MCR to work with
  - Map display
    - On task select, hide other tasks (bool)
- App level defaults on their own tab

### Mission Control: Simulate Mode (Paladin Only)
- **Mission Control Simulate mode:** add a simulation mode where live vehicle(s) test-run mission paths and feed results back into route refinement via trial-and-error updates. This is run by Paladin, but with operator standing by so that they can take over if a vehicle gets stuck and reroute so that the mission paths can be updated to account for it. This is basically mission testflighting.
- **Failure injection:** - build in intentional failure injections so that MissionControl/Paladin can react.

### Mission Control: Setup
- **Rosters:** 
  - **Live reserve swap-in** (replace active primary/wingman with reserve from **pool or fixed `.reserve` slot**): arm/calibrate, mission upload/resume, reposition, roster commit, disposition of replaced aircraft, map UX, class matching, escalation + manual + auto triggers — **`MissionRosterReservesToDo.md`**.

- **Settings:**
  - Add a tab for user to control MCR settings

### Mission Control: Running

- **MC-R reserve swap picker:** merit-ranked ordering (battery, proximity, link quality, etc.) for floating-pool health cards in the live roster strip; v1 uses ``enumerateReserveSwapCandidates`` order only (see ``MissionRunEnvironment/swapRosterAssignmentWithFloatingReservePoolSlot``).

- **Tasks:**
  - add functionality to tell task to complete/abort. (buggy)
  - add functionality to let user manage task controls (policies etc.)

- **Task Controls (Sidebar):**

- **Map:** 
  - Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.

- **Mission Controls (Sidebar):**

- **Vehicles:**
  
- **Vehicles (Sidebar):**

- **Settings:**
  - Add button in sub-bar using toggles icon
  - open drawer
  - allow user to manage MCR settings

#### Squads
- **Formations:** 
  - allow user to define a formation for the Squad to use. This overrides pattern behaviour.

### MissionRunEnvironment

#### Executor

- **MRE → `FleetCommandsCatalogue` + `FleetRecipeRunner`:** preferential abort/complete
  tactics (non–map-point) and between-cycles shaping route through catalogue + runner
  (README **Fleet Commands & Recipes** → Mission / MRE policy dispatch;
  `MissionRunRecipeOperatorPromptBridge` for in-run recipe escalations). Mission
  upload→arm→start runs through `recipe.fleet.do.mission.upload.start`. Further
  operator-prompt unification: `NEXTVERSION.md` (**Vehicle Inspector recipe wizard** — Revisit + Stage E).

#### Commander

#### Logging

#### Planner
- **MissionTask Squad Formations:** - defaults to patrol (cluster) and convoy (line), but add other formations later and allow incoming changes on the fly.

- **MissionTask Squad StaggerDelay:** - defaults to duration to first waypoint. Other options should be possible.
 - Value from MissionTask.staggerDelay object
 - Message from previous squad (squad primary radios in, next squad triggered) (fallback needed)

- **MissionTask Squad vehicle replacement:** 
  - build logic for swap in  a reserve to primary/wingman (same macro logic, different micro logic)

- **MissionTask Squad vehicle promotion:** 
  - build logic for wingman to be promoted to leader, and squad to update accordingly.
  - this is an RoE, that can be autonomous, ask etc.

- **MissionTask Squad vehicle release:** 
  - build logic for planner/operator/assistant to release a vehicle from roster slot completely. (Void the roster slot)
  - this is an RoE, that can be autonomous, ask etc.

- **Testing:** - test working with RoE.
- **Testing:** - test working with prompts.
- **Bug:** - mission builder not respecting heading: "follow path" when it is selected. Example mission had drone pointing in wrong direction. (Test Operation Themistokles) (Or drone not understanding)

#### Scheduling

- **MRE Scheduling:** 
  
- **AbortPolicy:** 
  - Trigger a task to move into aborting/aborted (buggy)

- **CompletePolicy:** 
  - Trigger a task to move into recovery/completed (buggy)

#### Logging

#### Tasks
  
  - **Complete:**
    - Currently we have to manually mark a task as complete after it begins that process. This should become autonomous as assignments check in that they have completed, and when all are there task is completed automatically.
  - **Abort:**
    - Currently we have to manually mark a task as aborted after it begins that process. This should become autonomous as assignments check in that they have aborted, and when all are there task is aborted automatically.

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

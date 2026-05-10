# TODO

## Vehicles System

- **Vehicle Calibration:**
  - Catalogue of calibration methods per telemetry element
    - If A is not working, calibration method is B
    - If C is not working, calibration method is D
  - Manual Calibration Process
    - Create a wizard process to calibrate a vehicle (live)
    - Create a wizard process to calibrate a vehicle (sim)
  
- **Vehicle Preflight:**
  - Attempt to arm, get errors and utilise calibration catalogue to solve


### Commands Catalogue

- **Commands:**
  - Build more generic commands
    - "Charge_Battery"
  - Build more specific commands
    - "Pull over"

- **Stack Converters:**
  - Build out PX4 converter
  - Build out AP converter
  
- **StepTypes:**
  - Add any missing step types


### Controllers System
The controllers system is designed to allow a user to control a linked vehicle with either their keyboard or a connected game controller/joystick. It will also possible to do a hybrid joystick + keyboard.

#### Keyboard

  - **Acceleration/Speed:** 
    - use a qualifier (Shift?) to adjust acceleration speed.

#### Game Controller


#### Joystick


## Clean Up
- Replace references to "path" with "task" so that we can get rid of legacy concept.

## App System

- Make clicking non-input UI areas unfocus the currently focused input field (desktop blur-on-background-click behavior).
- **Turn project into real .app:** this allows us to access lots of systems and permissions that our current swift build cannot.
- **UserNotifications:** hook into MacOS user notifications system so that MC-R can keep user updated if app is running in background. Include **MissionRunEnvironment → operator prompts** (see **Operator prompts subsystem** under `### MissionRunEnvironment`) when replacing the prompt stub with delivered notifications.
- **Internationalization (i18n):** expand localization coverage beyond Paladin log templates to full UI copy, formatting rules, and locale-aware defaults.
- **Extended Display Mode:** - convert app into extended display mode aware to allow user to have different main tabs on different displays (vehicles, logs, missions), and to allow them to do the same for MC-R.

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
- **Points:** - Add a points system for Tasks/Missions.
  - **Rally Points:** - Extend points with rally points for Tasks/Missions.
  - **Extraction Points:** - Extend points with extraction points for Tasks/Missions.
- **Mission Task.staggerDelay:** - Add a field (or fields) to control a tasks stagger delay between drone groups when method is staggered. (duration + time style e.g. 30+seconds, 10+mins, 1+hour)
- **Mission Task.geofence:** - Add a geofence limit around a MissionTask to say drones cannot exit it.
- **Mission Task.betweenCycles:** - Add a between cycles param to tell squads what to do between task cycles. These are actions.
  - Loiter, Park, RTL, Charge, GoToStart, GoToPoint etc.


### Mission Roster Slots

- **Roles:**
  - Develop roles for vehicles to give MC/assistants easier decisions
    - Guardian, Scout, and Marauder play different roles

## Mission Control

Mission Control is the system where mission templates are run by the Paladin system. Paladin in Guardian's mission brain, that reads mission templates and puts them into practive.

Mission Control includes Setup, Running, Recovery Completed as the main four states. It will also have a Simulation mode, where Paladin runs a mission template in a headless environment and reports back on its feasibility.

### Policies
- **Structure:**
  - Use Commands Catalogue
  - Allow chaining
  - Allow priority attempts + count (Try this policy first, then try that)

### Rules of Engagement
- **Rules:**
  - SquadPromote
  - RosterRelease
  - Abort

### Mission Control: Simulate Mode (Paladin Only)
- **Mission Control Simulate mode:** add a simulation mode where live vehicle(s) test-run mission paths and feed results back into route refinement via trial-and-error updates. This is run by Paladin, but with operator standing by so that they can take over if a vehicle gets stuck and reroute so that the mission paths can be updated to account for it. This is basically mission testflighting.
- **Failure injection:** - build in intentional failure injections so that MissionControl/Paladin can react.

### Mission Control: Setup
- **Rosters:** 
  - Allow user to add a pool of reserves to Task rosters by default.

### Mission Control: Running

- **Tasks:**
  - add functionality to tell task to complete/abort. (buggy)
  - add functionality to let user manage task controls (policies etc.)

- **Task Controls (Sidebar):**

- **Map:** 
  - Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.

- **Mission Controls (Sidebar):**

- **Vehicles:**
  - Calibration image colour-coded triage

- **Vehicles (Sidebar):**


#### Squads
- **Formations:** 
  - allow user to define a formation for the VG to use. This overrides pattern behaviour.

### MissionRunEnvironment

#### Executor

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

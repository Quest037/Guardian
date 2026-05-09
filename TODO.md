# TODO

## Vehicles System

- **Vehicle calibration flow:** add a guided, user-facing calibration/capability-check wizard (focused on real/live vehicles) that steps through connectivity, control, camera/gimbal, and telemetry checks, then records what this vehicle can/can't do so UI/automation can adapt safely.
- **Vehicle lifecycle detail level:** add a **General Settings** toggle to switch between **generic** `VehicleLifecycleStatus` messaging (default, stack-agnostic wording for non-expert users) and **detailed** status objects for power users (deeper stage granularity / richer diagnostics, including stack-specific context when useful).
- **Live vehicle type inference (MAV_TYPE → ``FleetVehicleType``):** SIM vehicles get their granular ``FleetVehicleType`` from the SITL preset at `registerSimulatedVehicle`, so logs and cards already show `[UAV-C:1]` etc. **Live** MAVLink vehicles currently default to `.unknown` (rendered `VEH:N`). Wire up MAV_TYPE inference: capture `MAV_TYPE` from the heartbeat (via `mavsdk_bridge.py` event or MAVSDK `Info`) once on first telemetry, map to ``FleetVehicleType`` (e.g. `MAV_TYPE_QUADROTOR/HEXA/OCTO/HELI` → `.uavCopter`, `MAV_TYPE_FIXED_WING` → `.uavFixedWing`, `MAV_TYPE_VTOL_*` → `.uavVTOL`, `MAV_TYPE_GROUND_ROVER` → `.ugvWheeled`, `MAV_TYPE_SURFACE_BOAT` → `.usv`, `MAV_TYPE_SUBMARINE` → `.uuv`), then call `FleetLinkService.setVehicleType(_:forVehicleID:)` to promote the model. Cards/logs/sub-bar will update automatically. Also extend `LiveDriveView.selectedVehicleClass` to read `model.data.vehicleType.universalClass` instead of guessing from `flightMode` strings.
- **Arm failure remediation catalog:** extend **`PreflightFailureAdvisor`** (`PreflightFailureAdvisor.swift`): add **pattern rules** (ordered entries in **`buildRules()`**) for remaining real-world **MAVSDK / STATUSTEXT** arm denials (battery failsafes, terrain, airspeed, logging, parachute, etc.); tighten **stack-specific** branches (ArduPilot vs PX4 vs **unknown**); use **`hubSnapshot`** fields (`health*`, GPS, RC) to **bias** steps when telemetry confirms or contradicts the message; add **unit tests** with log snippets; optional **`patternId` → localization / `PaladinLogTemplateKey`** for non-English operator copy; optionally mirror **`PreflightFailureRemediationAdvice`** into **fleet logs** or **Paladin events** on arm failure; reuse from **Vehicles grid preflight check** and any other preflight UX.

- **FleetVehicleModel / command surface:** expand control commands so all supported vehicle types can be driven manually with predictable behavior.
- **Input devices:** keyboard controls by default, plus support for connected Bluetooth/wired game controllers and joysticks. See full plan in **Live Drive: game controller / joystick integration** below.
- **Advanced control tuning (per SIM, with Settings defaults):** expose stack- and class-specific autopilot tuning to power users without making them open QGC / Mission Planner. **Live tune lives per running SIM**, defaults live in **Settings → SIMs → Advanced**, and any new SIM gets the defaults pushed at `registerSimulatedVehicle` time (alongside the existing PX4 `BAT1_CAPACITY` workaround in `applyMavlinkBatteryTelemetryTuningOnce`).
  - **Why:** params like `ATC_STR_RAT_P` (rover steering response), `CRUISE_SPEED`, `WPNAV_SPEED`, `MC_YAWRATE_P` change driving feel substantially. They're the difference between a "sluggish toy car" and a "silky rover" feel under LiveDrive.
  - **Plumbing already exists:** `FleetLinkService.getVehicleIntParameter(_:vehicleID:)` and `setVehicleIntParameter(_:value:vehicleID:)` work today against MAVSDK's `Param` plugin for any param name. Add `Float` variants (`getParamFloat`/`setParamFloat`) when we wire up since most tuning knobs are floats.
  - **Curate, don't expose raw param names.** ArduPilot has ~600 params, PX4 ~800 — a free-form editor will brick somebody's tune. Build a `VehicleTuningProfile` model keyed by `(FleetVehicleType, FleetAutopilotStack)` with abstract knobs (`steeringResponse: Soft/Default/Stiff`, `throttleResponse: Soft/Default/Stiff`, `cruiseSpeedMS: Double`, etc.) and per-stack mapping tables that translate the abstract knob to concrete param names + multipliers off stock values. Power users can still tune individual params in QGC/Mission Planner; we don't need to be the canonical full param editor.
  - **Stack + class gating is mandatory.** ArduPilot Rover's `ATC_STR_RAT_P` simply doesn't exist on PX4 multicopter; writing the wrong param to the wrong stack is at best a no-op and at worst a footgun. The Settings UI must filter knobs to those valid for the currently-selected `(FleetVehicleType, FleetAutopilotStack)` pair, and the spawn-time push must too.
  - **Architecture (3 slices):**
    1. **Tuning model layer.** New `Sources/GuardianHQ/VehicleTuningProfile.swift` — `struct VehicleTuningProfile: Codable, Equatable` plus `enum TuningKnob` (the abstract knobs) and `static let parameterMap: [TuningKnob: [FleetAutopilotStack: [FleetVehicleType: ParameterBinding]]]` where `ParameterBinding = (paramName: String, type: .int | .float, stockValue: Double, presetMultipliers: [softFactor, stiffFactor])`.
    2. **Persistence + apply helpers.** New `Sources/GuardianHQ/VehicleTuningStore.swift` paralleling `ManualControlSettingsStore` — holds `defaultsByTypeAndStack: [String: VehicleTuningProfile]` (the Settings defaults) and `liveOverridesByVehicleID: [String: VehicleTuningProfile]` (per-SIM live tunes). Add `FleetLinkService.applyTuningProfile(_:vehicleID:) async -> [TuningKnob: Result<Void, Error>]` that batch-writes via `param.setParamFloat`/`setParamInt`, returning per-knob success/failure for UI feedback. Call it from `SitlService.spawnArduPilot`/`spawnPX4` (defaults) and from per-SIM sheets (live).
    3. **UI.** Two surfaces:
       - **Settings → SIMs → Advanced**: per-(class, stack) preset cards. Each shows the abstract knobs with sliders/segmented pickers and a stack badge. Reuse `settingsRow` helper. Only edits the default; no live vehicle effect.
       - **Per-SIM "Drive tune" sheet** off the vehicle card or LiveDrive subbar (Settings cog icon, only visible when the vehicle is a SIM). Pulls current values from the live drone (`Param.getParamFloat`), shows them next to the abstract knobs with a "modified" diff indicator, and writes via `applyTuningProfile`. Add **Pull from vehicle** / **Push defaults** / **Reset to stock** buttons.
  - **SIM-only initially; live hardware extension later.** The first slice is intentionally SIM-only because (a) we control spawn and can guarantee param push timing, (b) bricking a SIM tune is recoverable in 5 seconds via respawn, and (c) we want to validate the abstract-knob mapping table on something disposable before pointing it at someone's $50k aircraft. Live hardware adds a "Pull from vehicle / Push to vehicle / Save as profile" UX layer on top of the same model — log as a follow-up.
  - **Don't build speculatively.** Wait until keyboard polish and controller integration give us concrete "this knob feels wrong" signal — building speculative knobs is how tuning UIs become unmaintainable graveyards.
  - **Vehicle Controls Acceleration/Speed:** - use a qualifier (Shift?) to adjust acceleration speed.

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

- **Convoy Task Design:** - Hook into OSM Routing system so that we can build convoy routes for tasks.
- **Custom Popup Mission Templates:** E.g. quick circle radius patrol with x vehicles.
- **Grid Card/List Card:** 
  - Get a map image snapshot as grid card image


### Mission Mechanics
- **Points:** - Add a points system for Tasks/Missions.
  - **Rally Points:** - Extend points with rally points for Tasks/Missions.
  - **Extraction Points:** - Extend points with extraction points for Tasks/Missions.
- **Mission Task.staggerDelay:** - Add a field (or fields) to control a tasks stagger delay between drone groups when method is staggered. (duration + time style e.g. 30+seconds, 10+mins, 1+hour)
- **Mission Task.timings:** - currently all fixed in minutes, allow variant of secs/mins/hrs
- **Mission Task.geofence:** - Add a geofence limit around a MissionTask to say drones cannot exit it.
- **Mission Task.betweenCycles:** - Add a between cycles param to tell squads what to do between task cycles. These are actions.

## Mission Control

Mission Control is the system where mission templates are run by the Paladin system. Paladin in Guardian's mission brain, that reads mission templates and puts them into practive.

Mission Control includes Setup, Running, Completed as the main three states. It will also have a Simulation mode, where Paladin runs a mission template in a headless environment and reports back on its feasibility.

Mission Control: Environment is the world environment that mission control uses when running missions. Paladin is bound to the environment.

### Mission Control: Simulate Mode (Paladin Only)
- **Mission Control Simulate mode:** add a simulation mode where live vehicle(s) test-run mission paths and feed results back into route refinement via trial-and-error updates. This is run by Paladin, but with operator standing by so that they can take over if a vehicle gets stuck and reroute so that the mission paths can be updated to account for it. This is basically mission testflighting.
- **Failure injection:** - build in intentional failure injections so that MissionControl/Paladin can react.

### Mission Control: Setup
- **Rosters:** - Allow user to add a pool of reserves to Task rosters by default.
- **AbortPolicy:** - Extend the abort policy system to allow other choices besides the default.
- **AbortPolicy:** - Extend the abort policy to allow tasks to override mission.
- **AbortPolicy:** - Extend the abort policy to allow roster cards to override task/mission.

### Mission Control: Running

**Tasks List:** - selectable and triggers expanded view of card with more data. Also shows all vehicles attached to task in health, and moves map (if necessary) to view task.

- **Tasks:** - can increment delays and cancel them, but cannot decrement delays. Also, it's tied to minutes but that should be seconds,minutes,hours as a second part of the choice.
- **Tasks:** - add ability for operator to start a task that is marked as operatorTriggered.
- **Tasks:** - add functionality for tasks that use onceAtStart, twiceStartEnd.
- **Abort:** - Remove stopAtEndOfCycle (if it still exists) and replace with stopAtEndOfCurrentCycles. This means that the mission winds itself down, making sure that the current cycle for each task is its last.
- **Map:** - Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.
- **RoE Updates:** - Allow the operator to update the RoE on the fly via a modal/overlay.

#### Vehicle Groups (Primary + wingmen)
- **Formations:** - allow user to define a formation for the VG to use. This overrides pattern behaviour.

- **Command accountability:** `MissionRunIssuedCommand` carries `issuer` + `issuerKey`; operator aborts use `MissionRunCommandIssuerKey.localOperator` until HQ has a stable operator identity (account/session), then re-stamp `issuerKey` from that id. Same for LiveDrive / other surfaces issuing fleet commands.  

### MissionRunEnvironment

#### Executor

#### Commander

#### Logging
- **MRE Policies Abort:** - make sure that range of options are viable for all vehicle types. "Land", doesn't work for anything but UAVs. Hold position is the same. "Park" would make more sense as all UVs can adhere to this concept.

#### Planner
- **MissionTask Squad Formations:** - defaults to patrol (cluster) and convoy (line), but add other formations later and allow incoming changes on the fly.

- **MissionTask Squad StaggerDelay:** - defaults to duration to first waypoint. Other options should be possible.
 - Value from MissionTask.staggerDelay object
 - Message from previous squad (squad primary radios in, next squad triggered) (fallback needed)

- **Squad vehicle replacement:** - build logic for swap in  a reserve to primary/wingman (same macro logic, different micro logic)
- **Squad vehicle promotion:** - build logic for wingman to be promoted to leader, and squad to update accordingly.
 - this is an RoE, that can be autonomous, ask etc.

- **Testing:** - test working with RoE.
- **Testing:** - test working with prompts.
- **Bug:** - mission builder not respecting heading: "follow path" when it is selected. Example mission had drone pointing in wrong direction. (Test Operation Themistokles) (Or drone not understanding)

#### Scheduling
- **MRE Scheduling:** - handle scheduling of tasks that are operatorTriggered.
- **MRE Scheduling:** - handle scheduling of tasks that are onceAtStart, twiceStartEnd.
- **MRE Scheduling:** - Remove stopAtEndOfCycle (if it still exists) and replace with stopAtEndOfCurrentCycles. This means that the mission winds itself down, making sure that the current cycle for each task is its last.

#### Logging
- **MRE Logging:** - When vehicles talk make sure to use their title (callsign) to identify them, if not already.
- **MRE Logging:** - Add a sub-system of Logging called Humanizing. It takes in log items and humanizes them for operators to understand better. (Makes it look like vehicles and assistants are actually speaking)

- **Operator prompts subsystem (MC-R):** v1 ships `MissionRunPromptsSubsystem` + `.swapInReserve` only (stacked FIFO, act-gated raise, planner → immediate executor batch — batch is empty until real resolution lands). Follow-ups:
  - **User Notifications:** replace `UserNotificationService.stubNotifyMissionRunOperatorPrompt` with real local notifications (category, thread by `runID`, copy for prompt kind + mission name + slot/path summary); align with **App System → UserNotifications** once the app runs as a proper `.app` and authorization is reliable. Optional notification actions (Accept/Decline) are a later UX decision — banner remains canonical while in-app.
  - **Planner / executor resolution:** implement `buildSwapInReserveResolutionPlan` beyond the no-op batch (roster mutations, mission re-upload, staged commands, or handoff — whatever MC-E + fleet policy requires); stamp `MissionRunIssuedCommand` issuer/issuerKey consistently with other operator-approved automation.
  - **Prompt taxonomy:** additional kinds beyond `.swapInReserve`;
  - **UI:** refine stacked-prompt UX (peek next, reorder, snooze/deadline if product wants it); add `PaladinLogTemplateKey` for accept/dismiss/raise if logs should be template-driven.
  - **Permissions / observers:** revisit whether any prompt operations beyond `.act` need finer gates once remote observers exist.
  - **MRE Learn:** - MRE instance can learn from operator prompts with operator permission. Such as, "do this from now on", so it can update RoE on the fly.

### Mission Control: Completed
- **Exporting:** export the mission report for outside app review. (Compact, Default, Full)


## Paladin System
Paladin is Guardian's mission running brain. It takes a mission template into mission control: running and executes it according to the specs and rules it is given.

- **Paladin Fleet readiness autopopulation:** wire `PaladinFleetPreflightBridge` into real preflight result callsites in `MissionControlStore` and `VehiclesView` flow so `PaladinFleetDomain` readiness updates automatically from probe outcomes. Allow Paladin to auto-calibrate vehicles if possible.
- **Paladin MissionRunAssistant on-demand vehicle telemetry queries (MAVSDK/MAVLink):** add a Paladin-specific active-query path so `MissionRunAssistant` can request immediate values (e.g. battery now, link health now, GPS/attitude now) rather than waiting for passive subscription refresh.

## Controllers System
- **Game controller / joystick integration:** add support for wired/wireless **game controllers** (Xbox, PS4/PS5, MFi, Stadia, Joy-Cons) and **HID joysticks / HOTAS** (Logitech Extreme 3D, T.16000M, Thrustmaster, etc.) as a first-class input alongside the existing `KeyboardEventMonitor` in `LiveDriveView`. Macos-only today; both transports (USB + Bluetooth) covered by system frameworks with no third-party deps.

  **Frameworks (no SwiftPM deps):**
  - `import GameController` (`GCController` / `GCExtendedGamepad`) for Xbox/PS/MFi/Stadia/Joy-Cons. Hot-plug via `GCControllerDidConnect`/`Disconnect`. Has battery, haptics (`GCController.haptics`), normalized layout.
  - `import IOKit.hid` (`IOHIDManager`) for non-MFi USB/BT joysticks and HOTAS that GameController doesn't surface. Lower-level enumeration, vendor/product IDs, raw axes/buttons.
  - When we sandbox the macOS app target (see Xcode Run → real `.app` task), add entitlements: `com.apple.security.device.bluetooth` (BT controllers), `com.apple.security.device.usb` (USB joysticks).

  **Architecture (mirror existing patterns):**
  - **New** `Sources/GuardianHQ/ControllerInputService.swift` — `@MainActor final class ControllerInputService: ObservableObject` paralleling `FleetLinkService`. Owns both the `GCController` notifications and an `IOHIDManager`. Publishes `connectedDevices: [InputDevice]`, `activeDeviceID: String?`, `lastSnapshot: ControllerSnapshot?`. Samples at 30–50 Hz via `DispatchSourceTimer`. Wire into `RootView` as `@StateObject` next to the other stores; pass into `LiveDriveView` and `SettingsView`.
  - **New** `Sources/GuardianHQ/ControllerBindingsStore.swift` — sibling of `ManualControlSettingsStore`. Holds `[ControllerProfile]` (id, name, `DeviceMatch`, `axisBindings: [AxisRole: AxisMapping]`, `buttonBindings: [ButtonRole: ManualControlAction]`, `deadzone`, `expoCurve`, `invertY`, per-axis `trim`/`scale`). UserDefaults JSON like the keyboard bindings. Ship 2–3 built-in profiles (Xbox/PS5 default UAV, Logitech Extreme 3D, generic HOTAS) plus per-`UniversalVehicleClass` defaults so picking a UAV auto-selects a UAV layout, a USV picks a marine layout, etc.
  - **`Sources/GuardianHQ/FleetVehicleModel.swift`** — add `case manualVelocitySetpoint(VelocityNED, yawRate: Double)` to `FleetVehicleCommand` for the analog stream path. Optionally add `.freeRoamGamepad` to `FleetVehicleCommandCategory` if we want to differentiate from `.freeRoamKeyboard` in arbitration. Discrete `case manualControl(ManualControlIntentCommand)` stays unchanged for buttons / dpad.
  - **`Sources/GuardianHQ/FleetLinkService.swift`** — add `startManualVelocityStream(vehicleID:)`, `updateManualVelocitySetpoint(...)`, `stopManualVelocityStream(vehicleID:)`. They own the **MAVSDK `Offboard` plugin** lifecycle (`Offboard.setVelocityNed(...)` resampled at ≥10 Hz, one-time `Offboard.start()` after seeding a zero setpoint, watchdog auto-`hold()` if no packet in ~750 ms). Long-lived `Disposable` stored on `VehicleSession` (alongside `session.bag`) for the duration of the freestyle session — **never** per-tick `Completable`s.
  - **`Sources/GuardianHQ/MissionControlStore.swift`** — every new `FleetVehicleCommand` case (e.g. `manualVelocitySetpoint`) needs the matching one-liner in `paladinShortCommandSummary` and any other exhaustive switches. The compiler will surface them.
  - **`Sources/GuardianHQ/LiveDriveStore.swift`** — add `controlMode: ControlMode { case keyboard; case controller(deviceID: String); case joystick(deviceID: String) }` and `activeInputDeviceID: String?`. `beginSession()` pins the input source to the session.
  - **`Sources/GuardianHQ/LiveDriveView.swift`** — replace the lone `KeyboardEventMonitor` with a unified `InputRouter` that subscribes to **both** `NSEvent` keys and `ControllerInputService.$lastSnapshot`. Discrete events (keys, buttons, dpad) → existing `.manualControl(...)` path (no `FleetLinkService` changes). Analog snapshots → `startManualVelocityStream` + `updateManualVelocitySetpoint` path. Sub-bar gets an "Input: Keyboard / *Controller name* / *Joystick name*" picker.
  - **`Sources/GuardianHQ/SettingsView.swift`** — extend `controlsPane` with two new sections: **Connected controllers** (live list from `ControllerInputService.connectedDevices`) and **Profiles** (CRUD on `ControllerProfile`s) using the existing `settingsRow` helper. Add a per-axis "wiggle to calibrate" sheet for IOHID joysticks (GameController doesn't need it).

  **Command-shape decision (most important):** every existing manual command in `completionForManualControl` is **discrete** — one keypress = one `gotoLocation` 2.5 m away. That's correct shorthand for taps and dpad presses, but it's the wrong abstraction for analog sticks (autopilot stutters between micro-targets). Use a **two-mode adapter**:
  1. **Discrete (existing pipeline):** keys, dpad, face buttons all stay on `.manualControl(ManualControlIntentCommand)`. Works on every supported vehicle today, zero changes needed for "Xbox-as-keyboard".
  2. **Analog (new):** sticks/triggers go through `.manualVelocitySetpoint(...)` + Offboard streaming. Gated behind:
     1. autopilot stack supports Offboard (PX4 + recent ArduPilot do),
     2. active input device is analog (`gamepad`/`joystick`),
     3. operator opted into "Direct stick control" in Settings (default off until validated per stack).

  **Authority + safety (reuse the existing ladder):**
  - Controller input maps to `manualTakeover` for the duration of a freestyle session — same priority as keyboard today, **don't** introduce a parallel gate.
  - **Deadman:** on `GCControllerDidDisconnect` or IOHID drop mid-session, immediately push `.holdPosition`, banner the operator, pause Offboard stream.
  - **Watchdog in `FleetLinkService`:** if no setpoint packet for ~750 ms, auto-`hold()` (defence in depth on top of MAVSDK Offboard's own timeout).
  - **Window-focus:** `NSEvent.addLocalMonitorForEvents` only fires when key window. `GCController` notifications fire regardless of focus — surface a `Settings → Controls → "Continue manual control while Guardian is in the background"` toggle (default **off** until we've thought through failure modes).
  - **Deadzone + idle collapse:** within deadzone for >250 ms → stream `setVelocityNed(0,0,0,0)`; sustained idle → one-shot `holdPosition`.

  **Per-class UX gotchas:**
  - Game pads self-center → "center = hold altitude". HOTAS throttle slider is unipolar 0..1 and stays where you put it — surface a per-axis `polarity: .bipolar / .unipolar` in `AxisMapping` so one code path handles both.
  - Store one default `ControllerProfile` per `UniversalVehicleClass`. UAV right-Y = climb; USV left-Y = throttle, right-X = rudder; UGV similar; UUV adds vertical from triggers.

  **MAVSDK Offboard landmines:**
  - `Offboard.start()` throws `NoSetpointSet` if you start it before any setpoint arrived — always seed one zero `setVelocityNed(...)` *before* `start()`.
  - ArduPilot mode-switch to GUIDED can take 100–300 ms on real vehicles — gate operator input on "mode confirmed via telemetry".

  **Rollout sequence (ship-as-you-go):**
  1. `ControllerInputService` (GameController only) + read-only "Detected devices" list in Settings → Controls. No control-flow changes — just see what shows up.
  2. `ControllerBindingsStore` with one default Xbox profile mapping dpad + face buttons onto existing `ManualControlAction` cases. Now Xbox-as-keyboard works through the **existing** `completionForManualControl(...)` with **zero** `FleetLinkService` changes — useful for `arm`/`engage`/`terminate`/`holdPosition` while Paladin runs the rest.
  3. Add `.manualVelocitySetpoint(...)` + Offboard streaming in `FleetLinkService`, gated behind a Settings toggle. Validate: PX4 SITL → ArduPilot SITL → real vehicles.
  4. Add `IOHIDManager` discovery so flight sticks / HOTAS show up in `connectedDevices`. Same `ControllerSnapshot`, second source.
  5. Polish: `GCController.haptics` cues on arm/takeoff/RTL, profile import/export, calibration sheet for IOHID joysticks.

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

## App System

- Make clicking non-input UI areas unfocus the currently focused input field (desktop blur-on-background-click behavior).
- **Turn project into real .app:** this allows us to access lots of systems and permissions that our current swift build cannot.
- **UserNotifications:** hook into MacOS user notifications system so that MC-R can keep user updated if app is running in background.

## Dashboard System

- Test the "Idle" card when a mission is running. Then test it when 2 missions are running side-by-side. See what it shows/what happens.

## Map System

- **CesiumJS 3D map spike (LiveDrive + MC Running):** evaluate replacing the current Leaflet 2D map in **LiveDrive** and **Mission Control Running** with a CesiumJS-based 3D map mode (camera follow/tracked entity, per-marker context menu parity, route/vehicle overlays, and acceptable telemetry update performance in `WKWebView`). Keep **Settings → default SIM coords** and mission authoring maps on lightweight 2D for now; this spike is for operational views first.
- Fix reset button gogin to a fixed zoom (it should use a bbox for everything)

## Live Drive

The Live Drive system allows a user to manually take control of a connected vehicle and send it commands to do things. The user can fly UAVs, drive UGVs etc. This works for both live vehicles and SIMs. This system can be used in freestyle, or can be the way the user takes control of a vehicle in a running mission.

- **LiveDrive takeover of live mission vehicle** Paladin will create a secret key for every vehicle in a mission. User can take over vehicle by inputting key and if Paladin has marked it for takeover. (So if you went cloudbased remote users could achieve this also)
- **LiveDrive takeover of live mission vehicle:** This has been coded, it needs testing properly when Paladin is capable of handing off vehicle to user.
- **LiveDrive map expansion:** Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.
- **LiveDrive UGV/USV/UUV RTL:** At the moment it just drives back in straight line, probably not likely to be able to achieve this. Needs consideration.

## Missions
Missions are the templates created by users that involve telling one or more vehicles what, when where and how to do what it needs to do.

- **Mission Path Rosters:** Figure out how to design rosters so that you can do tag-teams, back-ups, leader+followers etc. Also, look at fixed values for roster card "role", so that Paladin knows what to do with a vehicle by default. 
- **Custom Popup Mission Templates:** E.g. quick circle radius patrol with x vehicles & tag-team.

## Mission Control
Mission Control is the system where mission templates are run by the Paladin system. Paladin in Guardian's mission brain, that reads mission templates and puts them into practive.

Mission Control includes Setup, Running, Completed as the main three states. It will also have a Simulation mode, where Paladin runs a mission template in a headless environment and reports back on its feasibility.

Mission Control: Environment is the world environment that mission control uses when running missions. Paladin is bound to the environment.

### Mission Control: Simulate Mode (Paladin Only)
- **Mission Control Simulate mode:** add a simulation mode where live vehicle(s) test-run mission paths and feed results back into route refinement via trial-and-error updates. This is run by Paladin, but with operator standing by so that they can take over if a vehicle gets stuck and reroute so that the mission paths can be updated to account for it. This is basically mission testflighting.

### Mission Control: Setup
- MC-Setup is the authoring surface; the policy/fixture model it edits lives under **MC-E** below. (Slot↔vehicle binding, scheduling, and `simStartOverrideCoord` UX continue to live on the MC-Setup screens.)

### Mission Control: Running
- Integrate CesiumJS system to offer 3D map version as well as Leaflet 2D map.
- **MC-R Paladin reserve + handover orchestration:** (depends on **MC-E** rollout slices 3–4 for handover thresholds + role eligibility — this ticket is the *behaviour*; MC-E is the *config*.)
  - send reserve vehicles to take over when an active vehicle fails (when roster defines reserves),
  - perform path roster switchovers for low-battery tag-team operations when partner is ready,
  - analyze ahead of time (and continuously at runtime) to prepare handovers before thresholds are reached,
  - improve fault handling lifecycle: retry policy, give-up criteria, contingency triggers, and explicit operator intervention prompts.

### Mission Control: Completed

- **Internationalization (i18n):** expand localization coverage beyond Paladin log templates to full UI copy, formatting rules, and locale-aware defaults.


### Mission Control: Environment (MC-E)

- **Mission Control Environment (MC-E):** the authoritative artefact describing the conditions under which a `MissionRun` executes — the missing peer of **Plan** (route) and **Roster** (vehicles). Authored on the **MC-Setup** screens, consumed by **Paladin** at plan-compile and run time. This is what subsumes the previous scattered "set SIM battery %", "drain on/off per-SIM", "between-loop behavior policy", and "charging locations" tickets.
  - **Two cohabiting structs (the SIM-vs-live split is structural, not conditional):**
    1. `EnvironmentRules` — universal, applies to live + SIM (irrelevant fields are inert on the wrong side):
       - **Engagement (Rules of Engagement):** per-action records `{ disposition, triggers }`, **not** flat `Bool`s. Action classes: `rtl`, `land`, `forceDisarm`, `takeoverFromOperator`, `requestOperatorHandoff`, plus a default for unenumerated commands. Dispositions:
         - `.autonomous` — Paladin acts unilaterally.
         - `.ask` — Paladin wants to act, requests operator confirmation first (yes/no roundtrip; Paladin is the actor).
         - `.defer` — Paladin won't act until operator commands.
         - `.forbidden` — Operator must do this; Paladin won't even ask.
         - `.handoff` — **Paladin asks the operator to take over** (operator becomes the actor; Paladin steps back). Distinct from `.ask`: `.ask` is "may I do X?", `.handoff` is "you do X". Triggered by conditions like `.stuckForSeconds(60)`, `.geofenceBreachImminent`, `.batteryLowNoReserve`, `.gpsLostForSeconds(30)`.
       - **Handover thresholds (roster-internal):** battery %, time-to-empty, distance-from-home at which Paladin should swap in a reserve / tag-team partner. **Naming note:** intra-roster *handover* (SIM A → reserve SIM B) is distinct from operator *handoff* (Paladin → operator) — the existing `PaladinHandoffMode` (`PaladinService.swift:30`) is intra-roster and keeps that name; operator handoff lives entirely in the engagement slice above.
       - **Envelope:** geofence polygon, `maxAltitudeM`, `maxSpeedMS`, no-fly zones — Paladin refuses (or asks the operator) when commands would violate them. Envelope breaches are a primary trigger source for `.handoff` and `.ask` dispositions.
       - **Role eligibility:** `mayBePrimary` / `mayBeReserve` / `mayBeTagTeamPartner` / `mayBeChargingBuddy`.
    2. `SimFixtureEnvironment` — SIM-only, gated on `attachedFleetVehicleToken == .sitl`:
       - **Start state:** `startBatteryPercent`, `startPose` (today's `simStartOverrideCoord` collapses into this).
       - **Battery dynamics:** `drainEnabled` + `drainRate` (today's global `SimBatteryDrainRate` becomes the global default of this slice).
       - **Failure injection:** ordered `[SimFailureInjection]` script. Start with a fixed enum (`.batteryFailsafeAt(percent:)`, `.gpsLossAt(seconds:)`, `.linkDropAt(seconds:)`, `.simulatedReturnToLaunch`); resist building a DSL until pain demands it.
       - **Charging locations:** authored coordinates beyond mission home, persisted with the run.
  - **3-layer resolution (mirrors `simStartOverrideCoord`'s precedent):**
    - **Global default** in `GeneralSettingsStore`, optionally keyed by `(FleetVehicleType, FleetAutopilotStack)` so e.g. UGV-T and UAV-C carry different default envelopes.
    - **Per-run override** on `MissionRun.environmentRunOverride: EnvironmentRules?` and `simFixtureRunOverride: SimFixtureEnvironment?`.
    - **Per-slot override** on `MissionRunAssignment.environmentSlotOverride: EnvironmentRules?` and `simFixtureSlotOverride: SimFixtureEnvironment?`.
    - Pure `EnvironmentResolver.resolve(...) -> ResolvedEnvironment` collapses the three layers at plan-compile time. `PaladinPlan` carries `effectiveEnvironment: [AssignmentID: ResolvedEnvironment]` so runtime never re-walks the hierarchy. `nil` at any layer means "inherit from below."
  - **Architecture (5 slices):**
    1. **Model layer.** New `Sources/GuardianHQ/MissionControlEnvironment.swift` — `EnvironmentRules`, `SimFixtureEnvironment`, `ResolvedEnvironment`, `EnvironmentResolver`, plus `enum PaladinEngagementDecision { case allow; case ask(prompt:); case defer_; case forbidden(reason:); case handoff(reason:) }` and `enum PaladinEngagementDisposition` / `enum PaladinEngagementTrigger`.
    2. **Operator prompt channel.** New `Sources/GuardianHQ/PaladinOperatorPrompt.swift` — typed escalation channel parallel to `PaladinEvent`: `struct PaladinOperatorPrompt { id; severity; vehicleID; ask: PaladinPromptAsk; deadline: Date; autoAction: AutoAction }` where `PaladinPromptAsk` is `.confirmAction(...)` (for `.ask` disposition) / `.requestTakeover(reason:)` (for `.handoff` disposition) and `autoAction` says what happens if the operator doesn't respond by the deadline (`.continue` / `.rtl` / `.hold`). Routes through:
       - **Inline:** mission console + the relevant vehicle card banner.
       - **System:** macOS User Notifications (depends on the User Notifications TODO above).
       - **Inbound:** when operator clicks "Take over" on a `.requestTakeover` prompt, the handler raises the manual-takeover gate against the prompted vehicle (`FleetLinkService.setCommandAuthorityGate(...)`, already plumbed at `LiveDriveView.swift:451`) and opens LiveDrive on it. The empty placeholder at `LiveDriveView.swift:522` is the natural landing for this. **Connects directly to** the LiveDrive takeover ticket above (operator-initiated takeover); together they're the two directions of the same UX.
    3. **Model wiring.** Extend `MissionControlModels.swift` (add the optional override fields on `MissionRun` + `MissionRunAssignment`, with `Codable` migration tolerance for runs created before MC-E shipped), `GeneralSettingsStore.swift` (the global defaults), `PaladinService.swift` (`PaladinPlan` carries `effectiveEnvironment`, `PaladinRuntime.executeStagingPass` consumes `SimFixtureEnvironment`, plan-build consumes role eligibility).
    4. **Paladin engagement gate.** New `Sources/GuardianHQ/PaladinEngagementGate.swift` — single entry point `shouldIssue(_ command:, under: ResolvedEnvironment, telemetry:) -> PaladinEngagementDecision`. Every `commands.append(...)` site in `PaladinService` routes through it. The gate evaluates `disposition` first, then walks `triggers` against current telemetry to decide whether to emit a `PaladinOperatorPrompt`. Without this gate, "may RTL?" sprawls into a forest of inline `if`s — that's the bug we're avoiding.
    5. **UI.** Three surfaces, all reusing `settingsRow` + popover patterns we already have:
       - **Settings → Mission Control → Environment defaults** — tabbed editor (`Engagement (RoE)` / `Handover` / `Envelope` / `Role eligibility` / `SIM fixtures`). SIM-fixture defaults keyed by `(FleetVehicleType, FleetAutopilotStack)` so per-class defaults Just Work. Engagement editor: per action-class row, disposition picker + a triggers builder.
       - **MC-Setup run header → "Run environment overrides…"** sheet — same tabbed editor, only run-level fields, `"Inherits global"` badge on each unset field.
       - **MC-Setup slot inspector → "Slot environment overrides…"** sheet alongside the existing `simStartOverrideCoord` editor. SIM-fixture sheet hides itself when the slot's token is `.live`.
  - **Consumption points (single owner per slice — that's the litmus for whether the slice is well-shaped):**
    - `SimFixtureEnvironment.startBatteryPercent` / `drainEnabled` / `drainRate` / `startPose` → `PaladinRuntime.executeStagingPass`. Already calls `FleetLinkService.setSimBatteryDrainEnabled(...)`; needs new `setSimBatteryStartPercent(...)` (ArduPilot `SIM_BATT_VOLTAGE`; PX4 SIH has no clean knob — pre-spawn parameter file is the likely workaround, document the asymmetry).
    - `SimFixtureEnvironment.failureInjections` → new `Sources/GuardianHQ/PaladinFailureInjectionScheduler.swift` (run-lifetime, drains the script against wall-clock + telemetry triggers, emits `PaladinEvent`s on every injection).
    - `EnvironmentRules.engagement` + `.envelope` → `PaladinEngagementGate` (sole consumer of both). Gate emits `PaladinOperatorPrompt`s for `.ask` and `.handoff` decisions.
    - `EnvironmentRules.handover` → the runtime cycle planner that today produces `PaladinHandoffMode.thresholdDriven` (`PaladinService.swift`); replace the bool with the resolved threshold values.
    - `EnvironmentRules.roleEligibility` → plan-build role-track assembler. Ineligible reserve = setup-time blocker, not a runtime surprise.
  - **Live-vehicle scope:** `EnvironmentRules` applies universally; `SimFixtureEnvironment` is SIM-only. Live envelope enforcement is the most expensive bug surface — design the gate, ship the SIM path first, validate `.deny` on SITL before pointing it at a real aircraft.
  - **Rollout sequence (ship-as-you-go):**
    1. Model layer + resolver + plan-time integration. Empty UI. Verify resolved values land on `PaladinPlan` correctly via existing log surface (`PaladinEvent`). `PaladinOperatorPrompt` type lands here too (channel definition only — nothing emits or renders yet).
    2. SIM fixtures slice end-to-end: `startBatteryPercent`, `drainEnabled`/`drainRate` per-SIM (the existing global drain rate setting moves into the resolver as the global default). Settings + per-slot UI. This delivers the user-visible "MC-S battery state" + "drain on/off per-SIM" tickets as a side-effect.
    3. Engagement (RoE) + envelope through `PaladinEngagementGate`. Default every action class to `.autonomous` to start so no behaviour change; flip dispositions slice-by-slice as we validate. `.ask` rendering (mission console + vehicle card banner) lands here. `.handoff` triggers + system-notification rendering follow once macOS User Notifications ship.
    4. Handover thresholds replace `paladinTightCycleHandoff`. Unblocks "MC-R Paladin reserve + handover orchestration" below.
    5. Failure injection + charging locations.
  - **Cross-references:**
    - **Subsumes:** the standalone "SIM scenario commands" battery slice (top-of-file), "MC-S set battery state", "MC-S drain on/off per SIM", "MC-S between-loop behavior policy" + charging locations bullets.
    - **Unblocks:** "MC-R Paladin reserve + handover orchestration", "MC-R Simulate Mode" (Simulate Mode is just MC-R with a synthetic environment — no separate config surface).
    - **Independent (do NOT absorb):** vehicle autopilot tuning profile, LiveDrive controller integration, vehicle calibration flow. Tuning is "how the vehicle behaves on the wire"; environment is "the world it operates in."

## Paladin System
Paladin is Guardian's mission running brain. It takes a mission template into mission control: running and executes it according to the specs and rules it is given.

- **MC-E Vehicle API Key:** when Paladin runs a mission, it creates a secret API key for every vehicle involved. This key can be used by users to gain permission to take manual control of a vehicle during the mission to solve a problem.
- **Paladin: staging override execution:** during **Start Run**, apply each setup `simStartOverrideCoord` directly to the assigned SIM vehicle before path execution begins (authoritative pre-stage reposition step), emit Paladin events for success/failure per slot, and surface failures as setup blockers with actionable operator messaging. (Once **MC-E** lands, this generalises to "apply each slot's resolved `SimFixtureEnvironment` — pose, battery %, drain rate, scheduled failures — as one cohesive staging step." Keep this ticket as the active path until MC-E rollout slice 2 supersedes it.)
- **Paladin log copy / i18n:** every `PaladinEvent` carries a stable **`templateKey`** (see `PaladinLogTemplateKey` in `PaladinLogTemplates.swift`) plus **`templateParams`**; **`message`** stays the default English. To ship **our own wording** (or another language) without changing call sites, register format strings on **`PaladinLogTemplateRegistry.shared`** (e.g. `setTemplate(_:pattern:)` or `setTemplates`) using **`{{param}}`** placeholders that match the keys in `templateParams` for that event. Unregistered keys fall back to **`message`**. Next steps when we prioritize this: load patterns from **UserDefaults / JSON in the app bundle / `.lproj` string tables** keyed by `templateKey`, wire **locale** into the resolver, and optionally add a **Settings** UI to edit overrides. The live Paladin log and **`plainTextLine()`** export both resolve through the same registry.
- **Paladin Fleet readiness autopopulation:** wire `PaladinFleetPreflightBridge` into real preflight result callsites in `MissionControlStore` and `VehiclesView` flow so `PaladinFleetDomain` readiness updates automatically from probe outcomes.

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

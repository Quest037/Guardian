# Fleet Commands Catalogue — Reference (Layer 0)

Authoritative reference for the Layer 0 universal command catalogue. Companion to
`CommandsRecipesToDo.md` (the build tracker) and the architectural decisions captured
there. Read this when authoring a new command, a new stack converter, a new recipe
that consumes commands, or a plugin that contributes commands.

> **Layer reminder.** Commands are atomic, stack-translated, and stateless. Anything
> that branches on response, retries, escalates to an operator, or composes multiple
> outcomes belongs in **Layer 1 (Recipes)** — not here.

## 1. Namespace rules

### 1.1 Identifier shape

```
command.<addressing-segments>.<verb>.<specifier-segments>
```

- **`command.`** — mandatory prefix. Identifies the universal-bus namespace.
- **Addressing path** — one or more segments routing the command to its owning
  system / subsystem / plugin. v1 ships only `fleet.vehicle`; later milestones will
  add `mc.mre`, `plugin.<id>`, etc.
- **Verb** — exactly one segment from the closed reserved-verb dictionary.
- **Specifier** — one or more segments naming the operation. May contain dotted
  sub-segments (`calibrate.compass`, `move.altitude`).

### 1.2 Reserved verbs (closed set, v1)

| Verb     | Meaning                                                                                          |
|----------|--------------------------------------------------------------------------------------------------|
| `do`     | Mutate vehicle state (arm, set mode, calibrate, clear error). Side-effecting.                   |
| `get`    | Read cached / live state. Side-effect-free; usually returns a structured payload.               |
| `cancel` | Abort an in-progress long-running operation (calibration, mission upload).                       |

`subscribe` is intentionally **not** in v1. Streaming responses are deferred until a
real consumer needs them; existing telemetry pipes cover live data needs today.

### 1.3 Lexical rules

- Lowercase ASCII letters, digits, and dots only.
- No leading or trailing dot, no `..`.
- Maximum length 128 characters.
- At least one addressing segment AND one specifier segment.
- Exactly one verb segment in the identifier (verbs are reserved words).

`FleetCommandName.isValidRawValue(_:)` is the source of truth — keep this doc and the
validator aligned.

### 1.4 Ownership

- **Core** owns the addressing prefix `fleet.*` (and any future `mc.*`).
- **Plugins** own `plugin.<plugin-id-tail>.*`. v1 enforces this only by convention;
  Stage F adds machine-checked manifest namespace claims (see
  `CommandsRecipesToDo.md` Stage F).
- The catalogue's `register(_:)` is **last-write-wins per name**. Idempotent. A plugin
  cannot silently shadow a core command — they must use a different name (e.g.
  `command.fleet.vehicle.do.calibrate.compass.paladin`).

### 1.5 Composition (`containsCommands`)

A descriptor's `containsCommands` lists other registered command names this command
expands into when invoked. The catalogue invokes each child sequentially; first
failure short-circuits.

**Hard rule (v1):** composition is **strictly one level deep**. The catalogue refuses
to register a descriptor whose child has its own non-empty `containsCommands` list.
This eliminates cycle-detection burden and keeps audit traces flat.

Recipes (Layer 1) sit above commands and provide the deeper composition (`recipe →
recipe → command → command`, max-depth 4 in total).

## 2. Response taxonomy

Every Layer 0 invocation returns a typed `FleetCommandResponse`. Recipe authors **only
ever branch on the typed shape** — never on free-form failure strings.

### 2.1 Top-level `Outcome`

```swift
enum Outcome {
    case succeeded
    case error(kind: FleetCommandErrorKind)
    case cancelled
    case timeout
}
```

### 2.2 `FleetCommandErrorKind` (closed)

| Kind                          | Meaning                                                                |
|-------------------------------|------------------------------------------------------------------------|
| `unknownCommand`              | No descriptor registered for the requested name.                       |
| `noVehicle`                   | No `FleetVehicleModel` for the target vehicle ID.                      |
| `notConnected`                | Vehicle exists but lifecycle is not `.live`.                           |
| `noSession`                   | MAVSDK session unavailable (SITL not running, link down).              |
| `authorityGated`              | Authority gate / live-mission gate / live-drive gate refused dispatch. |
| `notImplemented`              | Stack converter has no translation for this command.                   |
| `dispatchFailed`              | Catalogue dispatch failed (parameter validation, internal plumbing).   |
| `alreadyArmed`                | Autopilot reports the vehicle is already armed.                        |
| `alreadyDisarmed`             | Autopilot reports the vehicle is already disarmed.                     |
| `armRejectedByAutopilot`      | Autopilot refused to arm (generic catch-all).                          |
| `calibrationDeclined`         | Autopilot refused to start a calibration procedure.                    |
| `calibrationDidNotConverge`   | Calibration started but failed mid-procedure.                          |
| `parameterRejected`           | Parameter set/get refused by autopilot.                                |
| `modeNotSupported`            | Autopilot does not support the requested mode for this state.          |
| `errorClearRefused`           | Autopilot has no fault to clear, or refused to clear it.               |
| `autopilotBusy`               | Autopilot is busy with a higher-priority operation.                    |
| `unknown`                     | Stack converter could not classify the raw outcome — escalate.         |

**Rule for stack converters:** every raw `FleetCommandAsyncOutcome.failed(String)`
must be classified into one of these kinds. When the heuristics cannot decide, return
`.unknown` — recipes should treat that as an unrecoverable failure and escalate.

Adding a new kind is a deliberate Layer 0 change: every recipe that branches on
`error.<kind>` may need to consider the new outcome, and every stack converter must
declare whether/when it produces it.

### 2.3 `FleetCommandResponsePayload`

```swift
enum FleetCommandResponsePayload {
    case empty
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case stringList([String])
    case keyValues([String: String])
}
```

Used primarily by `command.get.*` reads. Add a new case only when a real consumer
needs a richer shape — recipe-side matchers must also be updated.

## 3. Parameter schema

### 3.1 Declaration

Every descriptor declares its parameters via
`[FleetCommandParameterDeclaration]`. Each declaration carries:

- `name` (e.g. `"mode"`, `"meters"`).
- `type` — one of `bool | integer | double | string | stringList`.
- `isRequired` — when `true`, missing values cause `.error(.dispatchFailed)`.
- `allowedStringValues` (optional, `string` only) — closed allow-list.
- `humanLabel` — used by future wizard UI.

### 3.2 Validation

`FleetCommandsCatalogue.invoke(...)` runs every supplied
`FleetCommandParameters` bundle through `FleetCommandParameterValidator.validate(_:against:)`
before dispatching. Multiple failures are collected and joined into the response's
`detail` string (recipes / UIs can surface a complete picture in one round).

Two type-system conveniences:

- `integer` values are accepted where `double` is declared (so `35` and `35.0` are
  interchangeable for `meters`).
- `allowedStringValues` is an exact set match; values outside the set fail with
  `notInAllowedValues(allowed:actual:)`.

### 3.3 Codability

`FleetCommandParameterValue` is `Codable`. Recipes (Stage B) carry parameter literals
through their JSON DSL using this encoding.

## 4. Stack converters

Per-stack adapters live in `Subsystems/CommandsCatalogue/Stacks/`. v1 ships:

- `FleetCommandStackConverterArduPilot`
- `FleetCommandStackConverterPX4`
- `FleetCommandStackConverterUnknown` (fallback for `.unknown`)

### 4.1 Translation contract

`translate(...)` returns a `FleetCommandStackTranslation`:

| Case                     | Catalogue behaviour                                              |
|--------------------------|------------------------------------------------------------------|
| `.vehicleCommands([…])`  | Sequentially dispatch each `FleetVehicleCommand` via FleetLinkService. First failure short-circuits.|
| `.immediate(response)`   | Return `response` directly. Used by `get.telemetry.*` reads.     |
| `.notImplemented(detail)`| Catalogue returns `.error(.notImplemented)` with `detail` as the response detail. |

**Rule:** an empty `vehicleCommands([])` is interpreted as **no-op success**, not
"not implemented". Stack converters that intend `.notImplemented` must return that
case explicitly.

### 4.2 Normalisation contract

`normaliseOutcome(_:commandName:elapsed:)` converts every raw
`FleetCommandAsyncOutcome` into a typed `FleetCommandResponse`. The full
`FleetCommandName` is provided so converters can adjust classification per command
(e.g. "already armed" is `.alreadyArmed` for `do.arm` but `.unknown` for any other
command).

The shared helper `FleetCommandStackConverterShared.normaliseOutcome(...)` provides a
generic baseline. Stack-specific overrides live in the converter and call into the
shared helper for the catch-all path.

## 5. Risk tier

`FleetCommandRiskTier` documents how a command relates to the live-mission gate:

- `groundOnly` — must not be dispatched while the vehicle is in a live mission.
- `confirmInLiveMission` — allowed only after explicit operator confirmation.
- `safeInLiveMission` — safe in any state.

**Layer 0 does not enforce the tier.** Layer 1 recipe runners and Layer 2 process
surfaces honour it; the gate primitive is the existing
`MissionControlStore.isVehicleStreamUsedInLiveMission(...)` predicate, lifted to a
recipe-level guard in Stage B.

## 6. Built-in catalogue (v1)

| Command                                            | Risk tier                | Wired |
|----------------------------------------------------|--------------------------|-------|
| `command.fleet.vehicle.do.arm`                     | `groundOnly`             | ✓     |
| `command.fleet.vehicle.do.disarm`                  | `confirmInLiveMission`   | ✓     |
| `command.fleet.vehicle.do.mode`                    | `confirmInLiveMission`   | ✓ — every `FleetVehicleMode` token wired (PX4 raw `SET_MODE` via `Px4ModeCommander`; ArduPilot `mode <name>` via Shell plugin; class-aware on AP `hold`). PX4 `brake` and `surface` both return `.modeNotSupported` honestly (PX4 has no Brake mode and no UUV stack). `surface` is ArduSub-only on AP and non-Sub firmware will reject. Recipes verify mode actually changed via a follow-up `get.telemetry.mode`. |
| `command.fleet.vehicle.do.loiter`                  | `safeInLiveMission`      | ✓     |
| `command.fleet.vehicle.do.land`                    | `confirmInLiveMission`   | ✓     |
| `command.fleet.vehicle.do.surface`                 | `confirmInLiveMission`   | ArduPilot ✓ for UUV class only (dispatches `FleetVehicleCommand.setMode(.surface)` → `mode surface` over MAVSDK Shell → ArduSub mode 9). PX4 ✗ (no UUV stack). Non-UUV ArduPilot airframes return `.notImplemented` with the offending vehicle class. |
| `command.fleet.vehicle.do.return.home`             | `confirmInLiveMission`   | ✓     |
| `command.fleet.vehicle.do.move.altitude`           | `confirmInLiveMission`   | ✓ via shared converter → `FleetVehicleCommand.gotoCoordinate(...)`. `datum = asl|msl` target meters AMSL; `datum = agl` target meters above launch (ground AMSL derived from hub `absoluteAltM − relativeAltM`). Yaw preserved at current heading. Missing telemetry → `.notConnected` so recipes can branch. |
| `command.fleet.vehicle.do.move.heading`            | `confirmInLiveMission`   | ✓ via shared converter → `FleetVehicleCommand.gotoCoordinate(...)`. Offsets current lat/lon by `distanceM` along `headingDegrees` (spherical great-circle), keeps altitude (`relativeAltitudeM = 0`), and sets `yawDeg = headingDegrees` so the vehicle faces the direction of travel. Missing telemetry → `.notConnected`. |
| `command.fleet.vehicle.do.move.point`              | `confirmInLiveMission`   | ✓ for `pointKind = explicit` (lat/lon/relAlt/yaw → `Action.gotoLocation`) and `pointKind = currentLatLon` (re-target current lat/lon at new alt/yaw, lat/lon sourced from hub telemetry). `home` / `rally` not yet wired (no autopilot home / rally readback bridged into hub telemetry). |
| `command.fleet.vehicle.do.mission.upload`          | `confirmInLiveMission`   | ✓ via `FleetVehicleCommand.uploadMission(items:)` (atomic upload + reset current item to 0). Items pass through as JSON array under the `missionItemsJSON` parameter; the converter decodes via `FleetVehicleCommandMissionItemPayload`. Sibling `do.mission.*` verbs (start / pause / clear / jumpTo / download) are tracked in `TODO.md` and land incrementally. Arming and starting the mission are caller / recipe responsibilities. |
| `command.fleet.vehicle.do.calibrate.gyro`              | `groundOnly`           | PX4 ✓ via MAVSDK Calibration / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param1=1) |
| `command.fleet.vehicle.do.calibrate.accelerometer`     | `groundOnly`           | PX4 ✓ via MAVSDK Calibration / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param5=1) |
| `command.fleet.vehicle.do.calibrate.compass`           | `groundOnly`           | PX4 ✓ via MAVSDK Calibration / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_DO_START_MAG_CAL`) |
| `command.fleet.vehicle.do.calibrate.compass.motor`     | `groundOnly`           | PX4 n/a / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param6=1) |
| `command.fleet.vehicle.do.calibrate.compass.declination` | `groundOnly`         | PX4 ✓ (`ATT_MAG_DECL`) / AP ✓ (`COMPASS_DEC`, deg→rad) |
| `command.fleet.vehicle.do.calibrate.level`             | `groundOnly`           | PX4 ✓ via MAVSDK Calibration / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param5=2) |
| `command.fleet.vehicle.do.calibrate.baro`              | `groundOnly`           | PX4 ✓ / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param3=1) |
| `command.fleet.vehicle.do.calibrate.baro.temperature`  | `groundOnly`           | PX4 n/a / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param7=3) |
| `command.fleet.vehicle.do.calibrate.airspeed`          | `groundOnly`           | PX4 ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param6=1) / AP ✓ (`ARSPD_AUTOCAL=1`) |
| `command.fleet.vehicle.do.calibrate.battery.voltage`   | `groundOnly`           | PX4 ✓ (`BAT_V_DIV`) / AP ✓ (`BATT_VOLT_MULT`) |
| `command.fleet.vehicle.do.calibrate.battery.current`   | `groundOnly`           | PX4 ✓ (`BAT_A_PER_V`) / AP ✓ (`BATT_AMP_PERVLT`) |
| `command.fleet.vehicle.do.calibrate.battery.capacity`  | `groundOnly`           | PX4 ✓ (`BAT1_CAPACITY`) / AP ✓ (`BATT_CAPACITY`) |
| `command.fleet.vehicle.do.calibrate.esc`               | `groundOnly`           | PX4 ✓ / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param7=1) |
| `command.fleet.vehicle.do.calibrate.rc`                | `groundOnly`           | PX4 ✓ / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param4=1) |
| `command.fleet.vehicle.do.calibrate.rc.trim`           | `groundOnly`           | PX4 ✓ / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_PREFLIGHT_CALIBRATION`, param4=2) |
| `command.fleet.vehicle.do.calibrate.servo`             | `groundOnly`           | PX4 ✓ for main PWM bank (`PWM_MAIN_MIN<n>` / `PWM_MAIN_MAX<n>` / `PWM_MAIN_DIS<n>`; catalogue's `trimPwm` maps onto `PWM_MAIN_DIS<n>` because PX4 has no per-channel "trim" param; channel must be 1...16; AUX outputs are out of scope) / AP ✓ (`SERVO<n>_MIN/MAX/TRIM`) |
| `command.fleet.vehicle.do.calibrate.gimbal`            | `groundOnly`           | PX4 ✓ via MAVSDK Calibration / AP n/a |
| `command.fleet.vehicle.do.calibrate.gimbal.neutral`    | `groundOnly`           | PX4 ✓ (`MNT_OFF_*`) / AP ✓ (`MNT1_NEUTRAL_*`) |
| `command.fleet.vehicle.do.calibrate.rangefinder`       | `groundOnly`           | PX4 ✗ — **intentionally not wired**. PX4 lacks a stack-wide rangefinder param family (per-driver `SENS_EN_*` flags + EKF-side `EKF2_RNG_*` fusion tunings); recipe authors should use per-stack `do.param.set` once that atom lands. AP ✓ (`RNGFND1_*` family). |
| `command.fleet.vehicle.do.calibrate.flow`              | `groundOnly`           | PX4 ✗ / AP ✗ — **intentionally not wired**. PX4 (`SENS_FLOW_*` / `EKF2_OF_*`) and AP (`FLOW_*`) only overlap on mounting-position params; per-axis scalers and yaw orientation are stack-specific. Shipping a position-only atom would silently leave the rest mis-calibrated, so v1 declines. Use per-stack `do.param.set` for now. |
| `command.fleet.vehicle.do.calibrate.vision`            | `groundOnly`           | PX4 ✗ / AP ✗ — **intentionally not wired**. PX4 `EKF2_EV_*` and AP `VISO_*` only overlap on mounting-position params; pose alignment / fusion delay & noise are stack-specific. Same reasoning as `do.calibrate.flow`. |
| `command.fleet.vehicle.do.reboot.autopilot`            | `groundOnly`           | PX4 ✓ / AP ✓ — MAVSDK `Action.reboot()` (`MAV_CMD_PREFLIGHT_REBOOT_SHUTDOWN`). Universal "clear all transient state" since MAVLink has no generic clear-errors command. |
| `command.fleet.vehicle.get.telemetry.battery`          | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.compass`          | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.gps`              | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.estimator`        | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.flight`           | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.rc`               | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.link`             | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.get.telemetry.mode`             | `safeInLiveMission`    | ✓ |
| `command.fleet.vehicle.cancel.calibration`             | `safeInLiveMission`    | PX4 ✓ (`Drone.calibration.cancel()`) / AP ✓ via raw `COMMAND_LONG` (`MAV_CMD_DO_CANCEL_MAG_CAL`) |
| `command.fleet.vehicle.cancel.mission`                 | `confirmInLiveMission` | not yet wired |

"Not yet wired" / "✗" descriptors are registered in v1 (recipes can reference them)
but their stack converters surface `.error(.notImplemented)` with a stack-specific
detail string until the underlying autopilot pipeline lands. This is intentional:
the contract surface is real, the implementations follow incrementally.

### 6.1 Calibration command transports (cheat-sheet)

Three flavours of calibration. Recipe authors should know which one they're using
because retry / escalation strategy differs:

| Flavour                           | Transport                                            | Wired today                                      |
|-----------------------------------|------------------------------------------------------|--------------------------------------------------|
| Autopilot-driven sensor procedure | MAVSDK `Calibration` plugin progress stream          | PX4 only — gyro / accel / mag / level / gimbal   |
| Raw `MAV_CMD_PREFLIGHT_CALIBRATION` over MAVLink command-long | Guardian raw MAVLink v2 `COMMAND_LONG` UDP sender | PX4 baro / airspeed / ESC / RC / RC trim; AP gyro / accel / mag / compass-motor / baro / baro-temp / ESC / RC / RC trim |
| Param-driven `PARAM_SET` write    | MAVSDK `Param` plugin (`setParamFloat / setParamInt`)| Both stacks — declination, battery, gimbal neutral, AP servo / rangefinder / airspeed, PX4 servo. **Every catalogue-routed write is verified** by a follow-up `getParam*` read-back inside `FleetLinkService` (`completionForSetParameter{Float,Int}WithReadBack`); mismatch surfaces as `parameterReadBackMismatch` so recipes catch silent clamping / locked-param rejections. |

All three flavours surface the same `FleetCommandResponse` taxonomy. Recipes branch
on `error.notImplemented` to route a fallback path (e.g. when AP cannot run a sensor
cal, the recipe can fall back to declination set + capacity set + an operator escalation).

### 6.2 Calibration progress and cancellation (Layer 0 side channel)

Layer 0's `do.calibrate.*` commands still return a single terminal
`FleetCommandResponse`, but the MAVSDK Calibration plugin's progress stream is now
fanned out as a Combine publisher on `FleetLinkService`:

```swift
fleetLink.calibrationProgressEventsPublisher
    .filter { $0.vehicleID == myVehicleID }
    .sink { event in
        switch event.phase {
        case .progress:        // event.progressFraction, event.statusText
        case .operatorPrompt:  // event.statusText, e.g. "Rotate vehicle"
        case .completed:       // terminal
        case .cancelled:       // terminal — cancel.calibration was issued
        case .failed(let d):   // terminal
        }
    }
```

Recipes / wizards / plugins are responsible for routing `.operatorPrompt` events
into UI / toast / UserNotifications surfaces (no core operator-prompt channel
exists yet — that lands in Stage B1 / Layer 2 with the rest of the recipe
escalation contract). Cancellation runs through the existing
`command.fleet.vehicle.cancel.calibration` command issued in parallel; the in-flight
`do.calibrate.*` invocation surfaces a `cancelled` outcome (rather than
`error.unknown`) once the cancellation heuristic in the shared stack-converter
normaliser fires.

## 7. Authoring a new command

Five-step checklist:

1. **Pick a name** that satisfies §1.1–§1.3 and lives under the right ownership prefix.
2. **Add the literal** to `FleetCommandName+CoreLiterals` (or your subsystem / plugin's
   equivalent file).
3. **Register a descriptor** with `FleetCommandsCatalogue.shared.register(...)`.
   Declare:
   - parameters (and their schemas),
   - declared response kinds (start from `.standardDo / .standardGet / .standardCancel` and `.adding(...)` extras),
   - retry hints,
   - risk tier,
   - any `containsCommands` (one level only).
4. **Implement translation** in every stack converter that supports the command.
   Return `.notImplemented(detail:)` from converters where the underlying autopilot
   pipeline does not yet exist.
5. **Implement outcome normalisation** if the stack produces a failure phrasing not
   already covered by `FleetCommandStackConverterShared.normaliseOutcome(...)`.

That's it — no JSON edits, no wiring elsewhere. Recipes (Stage B) can reference the
new command by raw string and consume its typed responses.

## 8. Anti-patterns

- ❌ Encoding parameters into the namespace (`command.fleet.vehicle.do.mode.hold`). Use
  `do.mode` with a `mode` parameter.
- ❌ Returning `.vehicleCommands([])` from a stack converter to mean "not implemented".
  Return `.notImplemented(detail:)` explicitly.
- ❌ Branching on `response.detail` in a recipe. Recipes branch on `outcome` and
  `errorKind` only — `detail` is for logs / UI.
- ❌ Calling `FleetCommandsCatalogue.invoke(...)` directly from production UI in v1.
  Direct invocation is allowed (and used by tests / Stage B's runner) but
  user-facing callers should go through a recipe so they get retry / escalation /
  audit semantics.
- ❌ Catching outcomes in the catalogue's `invoke` and rewriting them. The catalogue
  is a thin pipeline — converters do all the classification.
- ❌ Adding a new verb. Reserved verbs are closed; widening the dictionary is a
  coordinated Layer 0 change.

## 9. File map

```
Sources/GuardianHQ/Systems/Fleet/Subsystems/CommandsCatalogue/
├── FleetCommandName.swift                       — typed identifier + validation
├── FleetCommandResponse.swift                   — outcome / error-kind / payload taxonomy
├── FleetCommandParameterSchema.swift            — parameter declarations + validator
├── FleetCommandDescriptor.swift                 — full per-command metadata
├── FleetCommandStackConverter.swift             — protocol for per-stack adapters
├── FleetCommandsCatalogue.swift                 — registry + invoke pipeline
├── FleetCommandsCatalogueBootstrap.swift        — idempotent registration entry point
├── Core/
│   └── FleetVehicleCoreCommandRegistrations.swift — v1 command literals + descriptors
└── Stacks/
    ├── FleetCommandStackConverterShared.swift   — telemetry payloads + outcome heuristics
    ├── FleetCommandStackConverterArduPilot.swift
    ├── FleetCommandStackConverterPX4.swift
    └── FleetCommandStackConverterUnknown.swift  — fallback for unidentified stacks
```

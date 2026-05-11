# Calibration recipe bodies

Per-recipe JSON files parsed by `FleetRecipeBodyParser` and loaded via
`FleetRecipeBodyLoader` from the subsystem's `registerAll()`. See README
"Layer 1 subsystems" for the hybrid contract; this directory holds the
**body half**.

The directory is named `CalibrationBodies` rather than just `Bodies` because
SPM flattens `.copy(<dir>)` resources to the bundle root — each subsystem
needs a uniquely-named bodies directory.

## File naming

Each file is named after the recipe it implements:

```
CalibrationBodies/<recipe.name>.json
```

Examples:

- `recipe.fleet.calibrate.compass.json`
- `recipe.fleet.calibrate.accelerometer.json`
- `recipe.fleet.diagnose.armprobe.json`
- `recipe.fleet.diagnose.armprobe.hold.json`

The loader resolves the file by `recipeName.rawValue`, so the filename and
the recipe's registered name must match exactly.

## Body shape

The JSON shape matches `FleetRecipeBody`'s `Codable` representation:

```json
{
  "entryStepID": "<step id>",
  "overallBudgetSeconds": 60,
  "steps": [
    {
      "kind": "invokeCommand",
      "id": "<step id>",
      "command": "command.fleet.vehicle.do.calibrate.compass",
      "matchers": [
        { "when": { "kind": "success" }, "then": { "kind": "succeed" } },
        { "when": { "kind": "any" }, "then": { "kind": "fail" } }
      ]
    }
  ]
}
```

See `FleetRecipeStep`, `FleetRecipeStepMatcher`, `FleetRecipeResponseMatcher`,
and `FleetRecipeControlOutcome` for the exhaustive `Codable` keys.

## Validation

The loader only **decodes** the JSON. Structural validation (matcher ordering,
branch targets, command/recipe registration, regex compilation, budget caps,
1-level composition depth) happens inside `FleetRecipesCatalogue.register(...)`
when the parent descriptor is registered — bodies that fail validation cause
the registration to be refused and the failure is logged.

## Content shipped so far

Five authoring patterns. Every recipe in patterns A–D is single-step and
declares `recipe.fleet.calibrate.cancel` as its `cancelRecipe` so mid-flight
cancel leaves the autopilot in a clean state. Pattern E (diagnose) ships a
separate cleanup recipe (`recipe.fleet.diagnose.cancel`) and references it.

**Cleanup recipe (1)**

- `recipe.fleet.calibrate.cancel.json` — atomic best-effort cleanup; declared
  as the `cancelRecipe` of every interactive calibration recipe.

**Pattern A — interactive, both stacks supported (8)**

5 matchers: `success → succeed`, `calibrationDeclined → escalate`,
`calibrationDidNotConverge → escalate`, `cancelled → fail`, `any → fail`.

- `compass.json` — 300s budget; declined → `removeMagneticInterference`,
  didNotConverge → `rotateDrone`.
- `accelerometer.json` — 300s budget; declined → `placeOnLevelSurface`,
  didNotConverge → `rotateDrone`.
- `gyro.json` — 60s budget; both failure kinds → `holdStill`.
- `baro.json` — 30s budget; both failure kinds → `holdStill`.
- `level.json` — 60s budget; both failure kinds → `placeOnLevelSurface`.
- `airspeed.json` — 60s budget; both failure kinds → `holdStill`.
- `esc.json` — 180s budget; both failure kinds → `restartVehicle`. **Dangerous**
  (motors spin); operator confirmation is the wizard's responsibility, not the
  runner's.
- `rc.json` and `rc.trim.json` — 180s / 60s budget; both failure kinds →
  `connectExternalSensor` (interpretation: verify the RC receiver is connected,
  transmitter on and bound).

**Pattern B — interactive, stack-asymmetric (3)**

6 matchers — Pattern A plus an explicit `error(notImplemented) → fail` matcher
with a clean "not supported on this stack" detail, so unsupported-stack
failures get a precise message instead of falling through to `any`.

- `compass.motor.json` — ArduPilot-only; PX4 → notImplemented-fail.
- `baro.temperature.json` — ArduPilot-only; PX4 → notImplemented-fail.
- `gimbal.json` — PX4-only (MAVSDK); ArduPilot → notImplemented-fail.

**Pattern C — v1 discoverability shells (3)**

4 matchers: `success → succeed`, `notImplemented → fail` (with a clean "not
implemented in this app version" detail), `cancelled → fail`, `any → fail`.
No recoverable-error escalations — failure mode is structural, not operator-
recoverable. Registered so Vehicle Inspector lists them; future stack support
flows in by wiring the converters, no recipe change.

- `rangefinder.json`
- `flow.json`
- `vision.json`

**Pattern D — param-driven writes (6)**

5 matchers: `success → succeed`, `parameterReadBackMismatch → fail`,
`parameterRejected → fail`, `cancelled → fail`, `any → fail`.

These recipes use `FleetRecipeParameterValue.reference` inside the JSON body to
forward descriptor-declared, caller-supplied values into the Layer 0 command:

```json
"parameters": {
  "degrees": { "kind": "reference", "value": "degrees" }
}
```

- `compass.declination.json` — parameter: `degrees: double`.
- `battery.voltage.json` — parameter: `scale: double`.
- `battery.current.json` — parameter: `scale: double`.
- `battery.capacity.json` — parameter: `mAh: integer`.
- `servo.json` — parameters: `channel`, `minPwm`, `maxPwm`, `trimPwm`.
- `gimbal.neutral.json` — parameters: `rollDeg`, `pitchDeg`, `yawDeg`.

**Pattern E — diagnose (3)**

The diagnose namespace lives in this bodies directory (single subsystem, single
`.copy(...)` resource) but the recipes are registered alongside the
calibrations by `FleetCalibrationRecipeRegistrations.registerAll()` after the
param-driven block. The cleanup recipe disarms instead of cancelling a
calibration procedure; the default probe is two-step (arm → disarm), with a
single-step hold variant for callers that must not disarm after a passing arm.

- `recipe.fleet.diagnose.cancel.json` — atomic best-effort disarm. Single
  matcher `any → succeed` so cancel mid-probe always leaves the vehicle
  disarmed if MAVSDK can be reached at all.
- `recipe.fleet.diagnose.armprobe.json` — 20s budget; the migration target
  for today's preflight overlay. Step 1 (`arm`) classifies the common
  autopilot refusal kinds the catalogue exposes today
  (`alreadyArmed → continue`, plus dedicated `fail` matchers for
  `armRejectedByAutopilot`, `calibrationDeclined`, `modeNotSupported`,
  `autopilotBusy`, `notConnected`, `noSession`, `authorityGated`). Step 2
  (`disarm`) is the safety floor — `success` / `alreadyDisarmed` succeed,
  `any` else fails loudly because a vehicle that armed but won't disarm is
  the worst-case probe outcome.
- `recipe.fleet.diagnose.armprobe.hold.json` — single `arm` step with the same
  refusal matchers as `armprobe` step 1, but `success` / `alreadyArmed` both
  `succeed` (no disarm). Used when `MissionControlStore` must leave the
  vehicle armed (Mission Control start-run roster probe, `leaveArmed` UI).

The subdirectory name is exposed as
`FleetCalibrationRecipeRegistrations.bodiesSubdirectoryName` so production
callers and tests reference the same string.

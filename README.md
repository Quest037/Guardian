# Guardian

Guardian is now a native macOS app shell built with SwiftUI.

## Current app shell

- Dark-first HQ interface
- Left navigation: `Dashboard`, `Devices`, `Missions`, `Mission Control`
- Top bar with app title
- Per-page content title/subtitle so navigation changes are obvious

## Build and run

From the `Guardian` directory (SwiftPM):

```bash
swift build
swift run GuardianHQ
```

Or use the Makefile (also fetches bundled `mavsdk_server` on first build), then run the binary SwiftPM emitted (path varies by architecture):

```bash
make build
"$(swift build --show-bin-path)/GuardianHQ"
```

Open the package in Xcode if you prefer:

```bash
open Package.swift
```

Then **Product → Run** (⌘R). Xcode uses the same SwiftPM target.

### Optional one-time dependencies (SITL / bridge)

- **ArduPilot SITL bundle:** `make sitl-runtime` — Python for `sim_vehicle`: `make sitl-deps`
- **PX4 SITL runtime slice** (`bin/px4` + `etc/`): build PX4 elsewhere, then `PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot make px4-sitl-runtime`
- **Prewarm both SITL stacks:** `make sitl-prewarm` (ArduPilot full prebuild), or include PX4 too: `PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot make sitl-prewarm`
- **MAVSDK-Python bridge:** `make bridge-deps`

## SITL command-catalogue smoke tests

End-to-end coverage for the Layer 0 fleet command catalogue (`command.fleet.vehicle.*`) ships as an **opt-in** XCTest suite, `GuardianHQSitlSmokeTests` in `Tests/GuardianHQTests/`. It is not part of normal `swift test` runs because it boots real **ArduPilot** and **PX4** SITL instances, starts `mavsdk_server` sessions, and drives the real `SitlService` → `FleetLinkService` → `FleetCommandsCatalogue` path against them.

### Run the suite

The canonical entry point is the repo script:

```bash
scripts/run_sitl_smoke_tests.sh
```

The script sets `GUARDIAN_RUN_SITL_SMOKE=1` and filters `swift test` to the smoke suite. Without that env var, the tests `XCTSkip` themselves so `swift test` (CI, dev loop) stays fast and deterministic.

Prerequisites are the same as for in-app SITL: bundled ArduPilot tree (`make sitl-runtime` or developer checkout via `GUARDIAN_ARDUPILOT_ROOT`), PX4 SITL slice (`make px4-sitl-runtime` or `GUARDIAN_PX4_ROOT` pointing at a PX4-Autopilot checkout with `px4_sitl_default` already built), and the SITL Python deps (`make sitl-deps`).

### What it covers

In one shared session per stack, for both ArduPilot and PX4:

- **Telemetry reads** — every `get.telemetry.*` descriptor returns a populated `keyValues` payload.
- **Param-set calibration** — `do.calibrate.battery.capacity` round-trips through the catalogue's `PARAM_SET` + read-back path.
- **Set-mode** — `do.mode mode=hold` succeeds and the autopilot's reported flight mode flips to a hold/loiter token.
- **Arm / disarm** — `do.arm` succeeds once the vehicle reports `healthArmable`, telemetry transitions to armed, then `do.disarm` brings it back down.
- **Loiter / return-home / land** — `do.loiter`, `do.return.home`, and `do.land` are accepted by the autopilot after re-arm.
- **PX4 calibration plugin** (PX4 only) — `do.calibrate.{gyro, level, gimbal}` exercises the MAVSDK Calibration plugin transport and surfaces a non-transport outcome (success, declined, did-not-converge, busy, etc.).

### Tuning timeouts

The harness honours these environment variables when set; otherwise it uses the defaults shown:

| Variable | Default (s) | Used for |
| --- | --- | --- |
| `GUARDIAN_SITL_SMOKE_BOOT_TIMEOUT` | `180` | Waiting for each SITL session to reach `.live` and for `healthArmable`. |
| `GUARDIAN_SITL_SMOKE_COMMAND_TIMEOUT` | `45` | Per-command catalogue dispatch budget. |
| `GUARDIAN_SITL_SMOKE_SIDE_EFFECT_TIMEOUT` | `20` | Waiting for telemetry side-effects (armed state, mode change). |
| `GUARDIAN_SITL_SMOKE_CALIBRATION_TIMEOUT` | `90` | PX4 calibration plugin per-procedure budget. |

### Extending it

When you wire a new command in `FleetCommandsCatalogue`, add a matching smoke assertion to `GuardianHQSitlSmokeTests` (in the same shared-session loop) per the **Add Tests For New Features** rule. Use `invoke(...)` + `assertSuccess(...)` for happy-path commands, and `assertNoTransportFailure(...)` for procedures whose autopilot-side outcome is non-deterministic in SITL (e.g. calibration progress).

## SIM battery drain (SITL)

Guardian can **turn simulated pack depletion on or off** for built-in SITL vehicles from **LiveDrive** and **Mission Control → Running**, so operational flows see realistic battery movement instead of a static 100%. This is **stack-agnostic in the app** but implemented with **different autopilot parameters** and **different simulator rules** on the wire.

### Where to configure it

- **Settings → SIMs → Default SIM battery drain rate** — Slow / Normal / Fast. This is the **fallback rate** when LiveDrive or Mission Control Running enables drain (not a global “always on” switch).
- **LiveDrive** — When a **SIM** is selected, use the **cog** in the sub-bar to open **SIM Live Settings**: toggle drain for that vehicle, pick a rate, and **Apply**. The sidebar explains PX4 vs ArduPilot behavior at a glance.

### What Guardian sets

| Stack      | Parameter          | When drain is **on** | When drain is **off** |
| ---------- | ------------------ | -------------------- | --------------------- |
| **PX4**    | `SIM_BAT_DRAIN`    | Positive float: full-discharge time in **seconds** (while the vehicle is **armed** in stock PX4 SITL). | `0` (disables the timed drain model). |
| **ArduPilot** | `SIM_BATT_CAP_AH` | Positive float: simulated pack capacity (**Ah**) for the SITL battery integrator. | `0` (static / non-integrating model for that path). |

Successful writes appear in the fleet log as `Param set [source=…] …` for the vehicle; failures show as `Param set failed …`.

### Autopilot semantics (why it can still read “100%”)

These rules come from the **simulators**, not from Guardian skipping a step.

- **PX4** — Stock `BatterySimulator` **only runs the discharge timer while armed**. While **disarmed**, it **resets** the simulated state of charge toward **full**. So LiveDrive or MC-R with a disarmed PX4 SIM will often look stuck at 100% even though `SIM_BAT_DRAIN` is set.
- **ArduPilot** — SITL battery charge moves with **integrated current**. **Near-zero motor current** (disarmed or idle throttle) means **little or no** visible drop for a long time.

To validate the feature: **arm** a PX4 SIM (or apply meaningful throttle on ArduPilot) and watch battery telemetry; confirm params in the log if in doubt.

## SIM state on the wire (`FleetSimState` / `applySimState`)

Guardian routes **every** programmatic SIM pose/SIM-parameter reset through one API so spawn, Mission Control‑E (MC‑E), and future “SIM recovery” actions stay aligned.

### Types

| Symbol | Location | Purpose |
| ------ | -------- | ------- |
| `FleetSimState` | `Sources/GuardianHQ/FleetSimState.swift` | Values to apply: lat/lon, optional AMSL-ish altitude, yaw, optional ArduPilot `SIM_BATT_*`, optional PX4 `SIM_BAT_DRAIN`. |
| `FleetLinkService.applySimState(vehicleID:state:autopilotStack:source:)` | `FleetLinkService.swift` | **Only** supported path to push those values to the autopilot over MAVSDK (built-in **Guardian SITL** streams only). |

Builders in use today:

- `FleetSimState(spawnDefaults:)` — mirrors **General → SIM spawn defaults** when reinforcing state after link-up (`source` typically `sitl.spawnHandshake`).

Other call sites build `FleetSimState` manually (or add new `init` helpers) then call `applySimState`.

### Autopilot wiring (what gets set)

**ArduPilot SITL:** `SIM_OPOS_LAT`, `SIM_OPOS_LNG`, `SIM_OPOS_ALT`, `SIM_OPOS_HDG`; optionally `SIM_BATT_VOLTAGE`, `SIM_BATT_CAP_AH` when the `FleetSimState` carries values.

**PX4 SIH SITL:** `SIH_LOC_LAT0`, `SIH_LOC_LON0`, `SIH_LOC_H0`; optionally `SIM_BAT_DRAIN` when set on state.

Launch recipes (`SitlLaunchRecipe`) still pass **CLI/env seeds** (`sim_vehicle.py -l …`, `PX4_HOME_*`); after MAVSDK reports **connected**, the spawn path schedules one `applySimState` (~0.5s delay) so Guardian and the autopilot agree on pose without duplicating unrelated launch logic in Swift.

### Guidance for Mission Control‑E (and agents)

When MC‑E (or tooling) needs to **teleport or reset SIM-facing params**:

1. Build a `FleetSimState` with the desired fields (reuse existing builders or populate manually).
2. Resolve `FleetAutopilotStack` for the vehicle (from fleet model / telemetry, same as other fleet code).
3. `await fleetLink.applySimState(vehicleID:vID, state:, autopilotStack:, source:"mc.phaseName")`.

Do **not** add parallel `setVehicleFloatParameter` call sites for the same SIM_OPOS / SIH_LOC family—extend `FleetSimState` / `applySimState` instead so UX and logs stay coherent.

## Live Drive control session (freestyle & mission, SIM & live)

While a Live Drive session is active, `FleetLinkService` sets **`liveDriveControlSessionVehicleID`** (`setLiveDriveControlSessionVehicle` / `clearLiveDriveControlSessionVehicleIfMatches`). Only that vehicle may receive **`liveDrive.*`** commands with **`.manualTakeover`** or run **manual control streaming** (`startManualControlStream`, `updateManualControlIntent`). This applies to **SIM and real aircraft**; **freestyle** and **mission** handoff both use the same gate (session kind is stored on `LiveDriveSessionRecord` for export). Param-only paths (e.g. SIM battery drain from the cog) are not gated by this.

## Adding another autopilot “stack” later

Rough checklist so fleet badges, sim picker, and MAVLink stay consistent:

1. **`FleetAutopilotStack`** (`Sources/GuardianHQ/FleetAutopilotStack.swift`) — add a `case`, `displayName`, and `badgeBackground` for the new stack.
2. **`SimulationPlatform`** (`Sources/GuardianHQ/SimulationCatalog.swift`) — add a case if Guardian will **spawn** that stack from the app; wire the picker and `SitlService`.
3. **Live vehicle detection** — extend `mavsdk_bridge.py`: after `connect()`, map vendor/product (or MAV enums) to the same **lowercase** string you use as `FleetAutopilotStack.rawValue`, and emit `{"type":"vehicle_stack","stack":"<raw>"}`. Handle it in `FleetLinkService.handleBridgeStdoutLine` (already decodes `vehicle_stack`).
4. **SITL launch** — implement a recipe in `SitlLaunchRecipe.swift` / `SitlService.swift` (see ArduPilot and PX4 paths).

Keep `vehicle_stack` JSON values aligned with `FleetAutopilotStack` `rawValue` strings (`ardupilot`, `px4`, `unknown`, plus any new cases).

## Child processes and cold launch (orphan cleanup)

After a **force quit**, macOS can leave Guardian-spawned subprocesses running. On each **cold app launch**, `GuardianSitlOrphanBlitz` tears down known orphans: persisted root PIDs from `GuardianSitlSpawnRegistry`, ArduPilot/PX4-oriented `pgrep` patterns derived from `SitlLaunchRecipe`, and the **whole process tree** under each matched root (so helpers like MAVProxy or `px4-mavlink` go away with the parent).

**If you add new spawn methods or long-lived services**—including anything **outside** ArduPilot/PX4—you need to keep that behavior correct:

1. Prefer spawning through **`SitlProcessRunner`** (or the same registration hook it uses) so the root PID is recorded in **`GuardianSitlSpawnRegistry`** after `Process.run()` succeeds, and unregistered when the process exits cleanly.
2. If the new stack cannot use `SitlProcessRunner`, you must still **register** the root PID (same registry API) and ensure **`GuardianSitlOrphanBlitz`** can find it again after a crash—typically by adding **narrow, path-specific** `pgrep` patterns (see existing ArduPilot/PX4 patterns) so unrelated user processes are never matched.
3. For local debugging only, `GUARDIAN_SKIP_SITL_ORPHAN_BLITZ=1` disables the startup blitz.

Skipping the above leaves orphans after force quit and breaks the expectation that Guardian cleans up everything it started.

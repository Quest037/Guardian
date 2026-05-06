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

## Adding another autopilot “stack” later

Rough checklist so fleet badges, sim picker, and MAVLink stay consistent:

1. **`FleetAutopilotStack`** (`Sources/GuardianHQ/FleetAutopilotStack.swift`) — add a `case`, `displayName`, and `badgeBackground` for the new stack.
2. **`SimulationPlatform`** (`Sources/GuardianHQ/SimulationCatalog.swift`) — add a case if Guardian will **spawn** that stack from the app; wire the picker and `SitlService`.
3. **Live vehicle detection** — extend `mavsdk_bridge.py`: after `connect()`, map vendor/product (or MAV enums) to the same **lowercase** string you use as `FleetAutopilotStack.rawValue`, and emit `{"type":"vehicle_stack","stack":"<raw>"}`. Handle it in `FleetLinkService.handleBridgeStdoutLine` (already decodes `vehicle_stack`).
4. **SITL launch** — implement a recipe in `SitlLaunchRecipe.swift` / `SitlService.swift` (see ArduPilot and PX4 paths).

Keep `vehicle_stack` JSON values aligned with `FleetAutopilotStack` `rawValue` strings (`ardupilot`, `px4`, `unknown`, plus any new cases).

# Guardian

Guardian is a **macOS mission console** for operating **uncrewed vehicles** — aerial drones, ground rovers, surface boats, and underwater platforms — from one place. You connect vehicles (real links or software simulators), plan missions on a map, run them under supervision, and take manual control when you need to.

Built with **SwiftUI**. Dark-first operator UI.

## How it works (big picture)

1. **Vehicles** — Add and monitor fleet units. Telemetry (position, battery, mode, health) streams in over MAVLink via a bridge to **MAVSDK**.
2. **Missions** — Author routes, tasks, roster slots, map points, and geofences on a mission template stored on disk.
3. **Mission Control** — Start a **run** from that template: bind simulators or live vehicles to roster slots, stage the plan, then **run** with live maps, logs, reserve pool, and automated fleet commands/recipes.
4. **Live Drive** — Fly or drive one vehicle manually (keyboard/gamepad-style control) with an optional mission map overlay.
5. **Logs & prompts** — Mission and fleet events are recorded; urgent decisions can surface as **operator prompts** (including out-of-app notifications when packaged as a `.app`).

Simulators (**SITL**) for ArduPilot and PX4 let you exercise the same flows without hardware.

## Main app areas

| Area | What you do there |
| --- | --- |
| **Dashboard** | Fleet-wide snapshot and entry points. |
| **Vehicles** | Fleet list, connection, inspection, preflight, calibration recipes. |
| **Missions** | Create and edit mission templates (paths, rosters, geofences, map points). |
| **Mission Control** | Setup a run, start/pause/recover, live map, roster triage, floating reserves. |
| **Live Drive** | Manual control session for one vehicle (freestyle or during a mission). |
| **Logs** | Browse operational and mission-run history. |
| **Settings** | App defaults, sim spawn, mission-run preferences, Live Drive options. |
| **Theme / Plugins** | Design catalog and optional extensions (e.g. Paladin integration). |

## Systems (code layout)

Under `Sources/GuardianHQ/Systems/`:

| System | Role |
| --- | --- |
| **Fleet** | Vehicle models, MAVLink hub, command & recipe catalogues, SITL lifecycle, preflight. |
| **Missions** | Mission template store, editor UI, geofences, mission points, thumbnails. |
| **Mission Control** | Run envelope (`MissionRunEnvironment`), planner, slot policy, MC setup & running UI, reserve pool. |
| **Live Drive** | Control sessions, manual input, map sync with an active mission when applicable. |
| **Operator prompts** | Routing, review focus, notifications for decisions that need a human. |
| **Dashboard** | High-level fleet/mission shell content. |
| **Logs** | Log browsing and retention hooks. |
| **Utilities** | Shared helpers (maps, geofences, live Leaflet marker builder, mission math). |

**Global design & map stack** live under `General/` (theme tokens, `GuardianMapView` → WebKit/Leaflet maps). **Plugins** under `Plugins/` register extra fleet recipes, UI, or integrations.

## Build and run

From the repo root:

```bash
swift build
swift run GuardianHQ
```

Or: `make build` then run the binary from `swift build --show-bin-path`. Open `Package.swift` in Xcode and **Product → Run** (⌘R).

Optional SITL/bridge setup: see **[README_FULL.md](README_FULL.md)** (dependencies, smoke tests, environment variables).

## More documentation

| Document | Contents |
| --- | --- |
| **[README_FULL.md](README_FULL.md)** | Contributor reference: architecture, locked product rules, SIM battery, reserve pool, map performance, fleet recipes, tests. |
| **[AGENTS.md](AGENTS.md)** | AI/agent entry points and links into rules & trackers. |
| **[TODO.md](TODO.md)** | Active engineering backlog. |
| **Live Leaflet map utilities** | `Sources/GuardianHQ/Systems/Utilities/LiveLeafletMap/` — shared live map markers, caching, hub apply throttle. |
| **[CommandsCatalogueDoc.md](CommandsCatalogueDoc.md)** | Fleet command & recipe catalogue notes. |

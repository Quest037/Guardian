# ROS 2 autonomy stacks (Nav2 + Aerostack2)

Guardian vendors upstream **Nav2**, **Aerostack2**, and **`as2_platform_pixhawk`** under `upstream/` for local colcon builds and future app integration. Source trees are **not committed** to git (same pattern as `ArduPilotSitl/`).

## Fetch

```bash
make ros2-autonomy-stacks-fetch
```

Optional overrides (must stay consistent with your installed ROS 2 distro):

```bash
GUARDIAN_ROS2_DISTRO=humble \
GUARDIAN_NAV2_REF=humble \
GUARDIAN_AEROSTACK2_REF=main \
GUARDIAN_AS2_PLATFORM_PIXHAWK_REF=main \
./scripts/fetch_ros2_autonomy_stacks.sh
```

Pinned defaults live in `manifest.json`. After fetch, `.guardian_ros2_autonomy_lock` records resolved commits.

## Layout

| Path | Role |
|------|------|
| `upstream/navigation2/` | [Nav2](https://github.com/ros-navigation/navigation2) — UGV / USV planners |
| `upstream/aerostack2/` | [Aerostack2](https://github.com/aerostack2/aerostack2) monorepo — UAV planners |
| `upstream/as2_platform_pixhawk/` | PX4 platform plugin for Aerostack2 |

## Build into the app (`make ros2-runtime`)

After fetch, run from the Guardian repo (ROS 2 Humble or Jazzy required on the build machine):

```bash
make ros2-runtime
```

This colcon **merge-installs** upstream sources plus `guardian_ros2_vehicle_bridge` into `Resources/Ros2Runtime/install/`. Guardian sources that single `setup.bash` at runtime — no Settings or manual workspace setup.

Optional faster dev build (skip heavy stacks):

```bash
GUARDIAN_ROS2_SKIP_NAV2=1 make ros2-runtime
```

## Guardian app bundle

`Package.swift` copies `Ros2AutonomyStacks/` (manifest + markers) and `Ros2Runtime/` (merged install when built). `make build` runs `ros2-runtime` automatically (same as `fetch_mavsdk_server.sh`).

## Related

- `Resources/Ros2VehicleBridge/README_AUTONOMY.md` — planner routing (v1 stubs)
- `TODO.md` — Vehicles System → autonomy integration backlog

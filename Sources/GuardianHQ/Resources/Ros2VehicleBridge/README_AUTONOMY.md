# Guardian autonomy — Nav2 & Aerostack2

Guardian’s ROS 2 autonomy layer sits **on top of** the PX4 uXRCE connection in `guardian_ros2_vehicle_bridge`. MAVSDK remains primary for arming, modes, missions, and fleet telemetry.

## Product lock

| Domain | Planner | Vehicle classes |
|--------|---------|-----------------|
| Ground / surface | **[Nav2](https://github.com/ros-navigation/navigation2)** | UGV-W, UGV-T, UGV-L, USV |
| Aerial | **[Aerostack2](https://github.com/aerostack2/aerostack2)** | UAV-C, UAV-F, UAV-V |
| Marine subsurface | *none (v1)* | UUV — planner TBD |
| Unknown | none | until class is known |

Swift routing: ``GuardianAutonomyPlannerRouting`` / ``Utilities.fleet.autonomy``.

Python routing: `autonomy_planner_kind.default_planner_for_class`.

## Architecture

```
GuardianHQ (FleetLinkService)
  └── FleetRos2BridgeCoordinator
        └── guardian_ros2_vehicle_bridge
              ├── Px4VehicleConnectionNode   (uXRCE telemetry — shipped)
              └── AutonomyPlannerCoordinator
                    ├── Nav2PlannerBridge      (UGV / USV — stub)
                    └── Aerostack2PlannerBridge (UAV — stub)
```

Stdout JSON when a vehicle is registered:

```json
{"type":"ros2_autonomy_planner","vehicle_id":"sysid:1","planner":"nav2","detail":{...}}
```

## ROS sidecar rollout (fleet target)

The **ROS 2 vehicle bridge** (Micro XRCE-DDS Agent + `guardian_ros2_vehicle_bridge`) is a **fleet-wide** subsystem: every PX4 **sim** and **live** vehicle that needs autonomy should eventually enroll in the same coordinator (`FleetRos2BridgeCoordinator` / `reconcileRos2Bridge`).

| Phase | Who enrolls | uXRCE at PX4 spawn | Notes |
|-------|-------------|-------------------|--------|
| **Now (testing)** | Training vehicle sim | yes (`SitlSpawnOwner.trainingRoster`) | Nav2 path overlay; MAVLink link before bridge start |
| **Next** | Formation squad sims, MCR PX4 streams | per-surface policy | Nav2 / Aerostack2 execution, not just map overlay |
| **Later** | Vehicles garage sims, live hardware | airframe / ops procedure | `registerSimulatedVehicle` / live link + `ensurePx4Ros2Sidecar(forVehicleID:)` |

Swift gate today: `px4Ros2SidecarDesiredVehicleIDs` in `FleetLinkService` (not “Training-only architecture”). Training is the first caller of `ensurePx4Ros2Sidecar(forVehicleID:)`; Formation and Mission Control will use the same API when their autonomy paths land.

**Do not** start the bridge at raw SITL register time for every garage spawn — wait until MAVLink position is up (`reconcileRos2BridgeAfterSimulatorLinked`), or first-sim connect regresses.

## v1 status (this repo)

- **Shipped:** planner kind per vehicle in config/YAML; Guardian publishes `autonomyPlannerByVehicleID`.
- **Fleet Nav2:** `nav2_training.launch.py` (open-field map + `planner_server`) starts **at application launch** via Swift ``FleetNav2StackRunner`` (`ros2 launch` + service probe). A headless ROS bridge host runs beside it (no PX4 vehicles required). The bridge uses in-app Python sources (`PYTHONPATH`) so `ensure_nav2` and planner polling stay current without rebuilding the colcon install. The bridge runs with **`python3` from the sourced ROS environment** (RoboStack / `~/.guardian/ros/humble`, typically 3.11) — not macOS/Xcode 3.9. Retries on timeout/launch error. Training debug rail shows **Nav2** vs **Python fallback**. Tune with `GUARDIAN_NAV2_READY_TIMEOUT_S` (default 120), `GUARDIAN_NAV2_MAX_START_ATTEMPTS`, `GUARDIAN_NAV2_RETRY_DELAY_S`. Rebuild Nav2 packages: `make ros2-runtime`. On macOS, launch/probe scripts set **`ROS_LOCALHOST_ONLY=1`** so the planner service is visible to Guardian subprocesses. Operator-facing status is **Swift-only** (``FleetNav2TrainingStackStatusPolicy``); bridge stdout poll must not reset a failed stack to “starting”. If the debug line stays on **Nav2 starting** past ~2 minutes, check the Training simulation log for `Fleet Nav2:` lines (launch stderr, timeout, or `nav2_launch_exited`).
- **Build:** `make ros2-runtime` installs Nav2 via RoboStack when possible; colcon-builds `navigation2` only if packages are missing. Skip with `GUARDIAN_ROS2_SKIP_NAV2=1`.
- **Not shipped:** Gazebo costmaps, `navigate_to_pose` execution, cmd_vel / offboard bridging; Aerostack2 missions; Formation / MCR autonomy dispatch.

## Configuration

Guardian assigns planner kind from vehicle class automatically when a PX4 session starts. Optional overrides in the sidecar YAML (`vehicles.yaml` / stdin `set_vehicles`):

```yaml
  - vehicle_id: "sysid:1"
    stack: px4
    vehicle_class: ugv_wheeled
    ros_namespace: ""
    autonomy_planner: nav2   # or aerostack2 | none
    enabled: true
    brain_id: "…"          # optional — Mission run binding
    brain_version: "0.0.2"   # semver; major 0 = subodai line
    nav2_param_overlay_json: "{...}"   # from Guardian Brain Pack planner_hints
```

Mission Control runs seed these fields via `GuardianBrainRos2SidecarPolicy` at execution start; overlays surface in `ros2_autonomy_planner` health JSON (param application to Nav2 nodes is not shipped yet).

## Bundled stacks

Nav2, Aerostack2, `as2_platform_pixhawk`, `px4_msgs`, and this bridge are built into `Resources/Ros2Runtime/install/` via `make ros2-runtime` (same out-of-the-box model as `mavsdk_server`). No operator setup in Settings.

## Related docs

- `README.md` — ROS 2 vehicle bridge setup (Micro XRCE-DDS Agent, `px4_msgs`).
- `TODO.md` — Vehicles System → live links + autonomy backlog.

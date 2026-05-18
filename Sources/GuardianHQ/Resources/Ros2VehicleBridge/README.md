# Guardian ROS 2 vehicle bridge

Python **rclpy** sidecar that opens a **second connection path** to each PX4 SITL or live vehicle alongside the existing **MAVSDK / MAVLink** bridge (`Resources/MavsdkBridge/mavsdk_bridge.py`).

```
PX4 SITL / live vehicle
  ├── MAVLink ──► mavsdk_bridge.py (primary: arm, modes, missions, fleet telemetry)
  └── uXRCE-DDS / ROS 2 ──► guardian_ros2_vehicle_bridge (PX4 topics, health, future autonomy APIs)
```

## Scope (this package)

- One ROS 2 node per configured vehicle (`vehicle_id`, `stack`, `vehicle_class`, `ros_namespace`, `enabled`).
- Discover / verify PX4 `fmu/out` topics from **uXRCE-DDS**.
- Subscribe to basic output topics when `px4_msgs` is installed (no command publishers yet).
- Connection states: `DISCONNECTED`, `CONNECTING`, `CONNECTED`, `DEGRADED`, `ERROR`.
- JSON lines on stdout for health / discovery (GuardianHQ runner can be added later).
- Stubs for future per-class command plugins (multicopter, fixed-wing, VTOL, rover, USV/UUV).
- **ArduPilot:** not implemented — `stack: ardupilot` is rejected with a TODO in code.

**Not in scope:** Nav2, Aerostack2, offboard setpoints, motion commands, or duplicating MAVSDK arming/mission behaviour.

## Bundled runtime (Guardian app)

Guardian ships ROS 2 like `mavsdk_server`: a merged colcon install under `Resources/Ros2Runtime/install/` plus `Resources/Ros2Runtime/bin/MicroXRCEAgent`. The app sources that environment automatically for every PX4 vehicle — no Settings paths or manual `source setup.bash`.

`make build` runs a **staged** ROS runtime step (requires `make ros2-system-install` first):

```bash
make ros2-system-install   # once: RoboStack Humble → ~/.guardian/ros/humble
make build                 # stage 1: px4_msgs + guardian_ros2_vehicle_bridge + swift build
make ros2-runtime-full     # optional: colcon-build Aerostack2 + Nav2 from upstream (slow)
```

Re-run stage 1: `GUARDIAN_FORCE_ROS2_RUNTIME=1 make ros2-runtime`

Upstream sources live under `Resources/Ros2AutonomyStacks/upstream/` (`make ros2-autonomy-stacks-fetch`).

## Dev-only colcon (without full runtime bundle)

```bash
source /opt/ros/humble/setup.bash
make ros2-autonomy-stacks-fetch
# … colcon in a workspace, or make ros2-runtime
```

`make ros2-bridge-deps` installs PyYAML for editable Python tests only.

## Configure vehicles

Copy `guardian_ros2_vehicle_bridge/config/vehicles.example.yaml` and set namespaces to match your PX4 XRCE clients.

| Field | Meaning |
|--------|---------|
| `vehicle_id` | Guardian key (teardown on remove/stop) |
| `stack` | `px4` only today |
| `vehicle_class` | `uav_copter`, `uav_fixed_wing`, `uav_vtol`, `ugv_wheeled`, … |
| `ros_namespace` | Prefix before `fmu/out/...` (empty → `/fmu/out/vehicle_status`) |
| `enabled` | Skip when `false` |

Environment: `GUARDIAN_ROS2_BRIDGE_CONFIG=/path/to/vehicles.yaml`

## Run with PX4 SITL

Typical terminal layout:

1. **Micro XRCE-DDS Agent** (port per PX4 docs, often UDP 8888):
   ```bash
   MicroXRCEAgent udp4 -p 8888
   ```
2. **PX4 SITL** with uXRCE enabled (see PX4 ROS 2 / DDS user guide for `UXRCE_DDS_*` params).
3. **ROS 2 daemon** (usually automatic once ROS is sourced).
4. **Health check** (one-shot):
   ```bash
   ros2 run guardian_ros2_vehicle_bridge guardian_ros2_health_check --namespace ""
   # exit 0 = all basic topics advertised
   ```
5. **Bridge** (multi-vehicle):
   ```bash
   export GUARDIAN_ROS2_BRIDGE_CONFIG=/path/to/vehicles.yaml
   ros2 launch guardian_ros2_vehicle_bridge vehicle_bridge.launch.py
   # or:
   ./scripts/run_vehicle_bridge.sh
   ```

Stdout emits JSON, e.g. `ros2_bridge_listening`, `ros2_connection_state`, `ros2_topic_discovery`.

Stdin (dynamic fleet, mirrors MAVSDK `set_system_ids` pattern):

```json
{"type": "set_vehicles", "vehicles": [{"vehicle_id": "a", "stack": "px4", "vehicle_class": "uav_copter", "ros_namespace": "", "enabled": true}]}
```

## PX4 topics (read-only)

Under each namespace, the bridge expects:

| Key | Topic |
|-----|--------|
| vehicle_status | `fmu/out/vehicle_status` |
| vehicle_local_position | `fmu/out/vehicle_local_position` |
| vehicle_global_position | `fmu/out/vehicle_global_position` |
| battery_status | `fmu/out/battery_status` |
| vehicle_odometry | `fmu/out/vehicle_odometry` |

## Architecture notes

- **MAVSDK** stays primary for fleet management until ROS command plugins are deliberately added.
- **This bridge** is for PX4-native ROS 2 / uORB access and **Nav2 / Aerostack2** planner routing (see **[README_AUTONOMY.md](README_AUTONOMY.md)**).
- Command stubs live in `guardian_ros2_vehicle_bridge/command_extension_points.py` (not wired to publishers).
- Future **ArduPilot** ROS 2 path: separate stack enum branch and topic map (TODO in `vehicle_config.py`).

## Package layout

```
Ros2VehicleBridge/
  README.md
  scripts/run_vehicle_bridge.sh
  guardian_ros2_vehicle_bridge/          # ament_python package
    package.xml
    setup.py
    config/vehicles.example.yaml
    launch/vehicle_bridge.launch.py
    guardian_ros2_vehicle_bridge/        # Python module
      multi_vehicle_bridge.py            # main entry
      px4_vehicle_node.py
      health_cli.py
      ...
```

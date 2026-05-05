# TODO

- **Built-in SITL:** bundle or ship signed helper binaries for **ArduPilot SITL** and **PX4 SITL**; spawn/stop processes from the app; assign **non-conflicting MAVLink ports and system IDs** per instance so multiple sims (e.g. three UAVs) can run in parallel and connect to `mavsdk_server` (or multiple server instances).
- **Simulation catalog:** implement launch profiles for each `SimulationVehiclePreset` × `SimulationPlatform` (vehicle model, frame args, UDP topology) and surface in UI (add sim vehicle, optional per-spawn stack override vs General default).
- **Mission Control:** UI to add/remove simulated vehicles, bind to mission rehearsal (N vehicles for N-aircraft missions), integrate with the top-bar **Simulate** toggle and **FleetLinkService** / MAVLink settings.
- **Mission Control → Mission view:** include an optional **3D view** (vehicle pose / scene) alongside the existing mission UI when we get to that milestone.
- Make clicking non-input UI areas unfocus the currently focused input field (desktop blur-on-background-click behavior).
- Replace the **MAVSDK-Python sidecar** (`mavsdk_bridge.py` / `MavsdkBridgeRunner`) with a **native Swift gRPC client** generated from the same MAVSDK proto revision as the bundled `mavsdk_server`, once APIs and shipping story are stable (remove Python runtime dependency for end users).

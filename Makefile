# Default: bundled mavsdk_server + Ros2Runtime, then swift build.
.PHONY: build bridge-deps ros2-bridge-deps ros2-autonomy-stacks-fetch ros2-system-install ros2-runtime ros2-runtime-full build-with-ros2 sitl-runtime sitl-deps sitl-patch-waf sitl-prewarm sync-simulation-devices px4_sitl_default px4-sitl-runtime stack-wiki-fetch stack-wiki-refresh stack-wiki-deps

# PX4 is not built from this repo; this target exists so `make px4_sitl_default` here explains what to run instead of "No rule".
px4_sitl_default:
	@echo "Guardian does not build PX4. Run the lines below from any parent folder (do not mkdir PX4-Autopilot first — that nests PX4-Autopilot/PX4-Autopilot)."
	@echo "After that, from the Guardian repo: PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot make px4-sitl-runtime"
	@echo ""
	@echo "  git clone https://github.com/PX4/PX4-Autopilot.git && cd PX4-Autopilot"
	@echo "  git submodule update --init --recursive"
	@echo "  make px4_sitl_default"
	@echo ""
	@exit 1
build: Sources/GuardianHQ/Resources/mavsdk_server Sources/GuardianHQ/Resources/Ros2Runtime/install/setup.bash
	swift build

Sources/GuardianHQ/Resources/mavsdk_server:
	./scripts/fetch_mavsdk_server.sh

Sources/GuardianHQ/Resources/Ros2Runtime/install/setup.bash:
	chmod +x scripts/build_ros2_runtime_bundle.sh scripts/fetch_ros2_autonomy_stacks.sh scripts/fetch_micro_xrce_agent.sh
	./scripts/build_ros2_runtime_bundle.sh

# One-time (large): ArduPilot SITL tree bundled under Resources/ArduPilotSitl for in-app sim_vehicle.py.
sitl-runtime:
	./scripts/fetch_ardupilot_sitl.sh

# Copy built PX4 POSIX SITL (bin/px4 + etc/) from PX4_AUTOPILOT_ROOT into Resources/Px4SitlBundle.
px4-sitl-runtime:
	./scripts/sync_px4_sitl_bundle.sh

# Re-apply waf git fallback on an existing ArduPilot tree (fixes SITL build when git rev-parse fails in bundles).
sitl-patch-waf:
	python3 scripts/patch_ardupilot_waf_git_fallback.py Sources/GuardianHQ/Resources/ArduPilotSitl/Tools/ardupilotwaf/git_submodule.py

# Copy Dev_Sim_*.png from Resources/SimulationDevices into Sources/…/SimulationDevices for SwiftPM bundling.
sync-simulation-devices:
	./scripts/sync_simulation_devices.sh

# One-time: Python modules for sim_vehicle / waf / MAVProxy (pexpect, empy, gnureadline, etc.).
sitl-deps:
	pip3 install -r Sources/GuardianHQ/Resources/SitlDeps/requirements.txt

# One-command prewarm:
# - ArduPilot: fetch runtime + prebuild copter/plane/rover/sub under build/sitl.
# - PX4 (optional): if PX4_AUTOPILOT_ROOT is set, build/sync bundled Px4SitlBundle too.
sitl-prewarm:
	./scripts/prewarm_sitl.sh $(PX4_AUTOPILOT_ROOT)

# Full local build including simulation files (run sitl-runtime before first SITL spawn).
.PHONY: build-with-sitl
build-with-sitl: Sources/GuardianHQ/Resources/mavsdk_server Sources/GuardianHQ/Resources/ArduPilotSitl/Tools/autotest/sim_vehicle.py
	swift build

Sources/GuardianHQ/Resources/ArduPilotSitl/Tools/autotest/sim_vehicle.py:
	./scripts/fetch_ardupilot_sitl.sh

# One-time (or after Python upgrades): MAVSDK-Python for the telemetry sidecar.
bridge-deps:
	pip3 install -r Sources/GuardianHQ/Resources/MavsdkBridge/requirements.txt

# Optional PyYAML for editable ROS 2 bridge install; ROS 2 + px4_msgs are separate (see Ros2VehicleBridge/README.md).
ros2-bridge-deps:
	pip3 install -r Sources/GuardianHQ/Resources/Ros2VehicleBridge/guardian_ros2_vehicle_bridge/requirements-dev.txt

# One-time (large): Nav2 + Aerostack2 + as2_platform_pixhawk under Resources/Ros2AutonomyStacks/upstream/.
ros2-autonomy-stacks-fetch:
	chmod +x scripts/fetch_ros2_autonomy_stacks.sh
	./scripts/fetch_ros2_autonomy_stacks.sh

# ROS 2 Humble at /opt/ros/humble (RoboStack). Run once per machine before first `make build`.
ros2-system-install:
	chmod +x scripts/install_ros2_macos.sh
	./scripts/install_ros2_macos.sh

# Staged Ros2Runtime: px4_msgs + bridge + Nav2 for Training (RoboStack or colcon). Skip Nav2: GUARDIAN_ROS2_SKIP_NAV2=1
ros2-runtime:
	chmod +x scripts/build_ros2_runtime_bundle.sh scripts/fetch_micro_xrce_agent.sh scripts/guardian_ros2_system_prefix.sh
	./scripts/build_ros2_runtime_bundle.sh

# Optional: also colcon-build Aerostack2 + Nav2 from upstream sources (slow; may need extra brew deps).
ros2-runtime-full:
	chmod +x scripts/build_ros2_runtime_bundle.sh scripts/fetch_micro_xrce_agent.sh scripts/guardian_ros2_system_prefix.sh
	GUARDIAN_ROS2_RUNTIME_FULL=1 ./scripts/build_ros2_runtime_bundle.sh

# Alias kept for older docs/scripts; same as `make build`.
build-with-ros2: build

# Dev-only: local PX4 + ArduPilot doc chunks for Cursor agents (Resources/StackWiki/, not app bundle).
stack-wiki-deps:
	pip3 install -r scripts/stack_wiki/requirements.txt

stack-wiki-fetch:
	./scripts/stack_wiki/fetch_upstream.sh

stack-wiki-refresh:
	./scripts/stack_wiki/refresh_stack_wiki.sh

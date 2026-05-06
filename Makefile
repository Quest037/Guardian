# Default: ensure bundled mavsdk_server exists, then build.
.PHONY: build bridge-deps sitl-runtime sitl-deps sitl-patch-waf sync-simulation-devices px4_sitl_default px4-sitl-runtime

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
build: Sources/GuardianHQ/Resources/mavsdk_server
	swift build

Sources/GuardianHQ/Resources/mavsdk_server:
	./scripts/fetch_mavsdk_server.sh

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

# Full local build including simulation files (run sitl-runtime before first SITL spawn).
.PHONY: build-with-sitl
build-with-sitl: Sources/GuardianHQ/Resources/mavsdk_server Sources/GuardianHQ/Resources/ArduPilotSitl/Tools/autotest/sim_vehicle.py
	swift build

Sources/GuardianHQ/Resources/ArduPilotSitl/Tools/autotest/sim_vehicle.py:
	./scripts/fetch_ardupilot_sitl.sh

# One-time (or after Python upgrades): MAVSDK-Python for the telemetry sidecar.
bridge-deps:
	pip3 install -r Sources/GuardianHQ/Resources/MavsdkBridge/requirements.txt

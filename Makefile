# Default: ensure bundled mavsdk_server exists, then build.
.PHONY: build bridge-deps
build: Sources/GuardianHQ/Resources/mavsdk_server
	swift build

Sources/GuardianHQ/Resources/mavsdk_server:
	./scripts/fetch_mavsdk_server.sh

# One-time (or after Python upgrades): MAVSDK-Python for the telemetry sidecar.
bridge-deps:
	pip3 install -r Sources/GuardianHQ/Resources/MavsdkBridge/requirements.txt

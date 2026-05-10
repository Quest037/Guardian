#!/usr/bin/env bash
# Runs the opt-in SITL smoke suite for the Layer 0 fleet command catalogue.
#
# This is intentionally separate from normal `swift test`: it boots real ArduPilot and
# PX4 SITL processes, starts mavsdk_server sessions, and drives Guardian's command
# catalogue end-to-end.
#
# Useful environment knobs:
#   GUARDIAN_SITL_SMOKE_BOOT_TIMEOUT=180
#   GUARDIAN_SITL_SMOKE_COMMAND_TIMEOUT=45
#   GUARDIAN_SITL_SMOKE_SIDE_EFFECT_TIMEOUT=20
#   GUARDIAN_SITL_SMOKE_CALIBRATION_TIMEOUT=90
#   GUARDIAN_ARDUPILOT_ROOT=/path/to/ardupilot
#   GUARDIAN_PX4_ROOT=/path/to/PX4-Autopilot

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export GUARDIAN_RUN_SITL_SMOKE=1

echo "[sitl-smoke] Running GuardianHQ SITL command-catalogue smoke tests."
echo "[sitl-smoke] This will boot ArduPilot and PX4 SITL in one shared test session."
echo "[sitl-smoke] Filter: GuardianHQSitlSmokeTests"

swift test --filter GuardianHQSitlSmokeTests "$@"

#!/usr/bin/env bash
# Prewarms bundled SITL runtimes so first in-app "Add Sim" does not block on compilation.
#
# ArduPilot:
#   - Ensures Sources/GuardianHQ/Resources/ArduPilotSitl exists.
#   - Builds common SITL binaries under build/sitl/bin once (copter/plane/rover/sub).
#
# PX4 (optional):
#   - If PX4_AUTOPILOT_ROOT is set (or first arg provided), ensures a SITL build exists
#     (runs `make px4_sitl_default` if needed), then syncs runtime into Px4SitlBundle.
#
# Usage:
#   ./scripts/prewarm_sitl.sh
#   PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot ./scripts/prewarm_sitl.sh
#   ./scripts/prewarm_sitl.sh /path/to/PX4-Autopilot

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AP_ROOT="$ROOT/Sources/GuardianHQ/Resources/ArduPilotSitl"
PX4_SRC="${PX4_AUTOPILOT_ROOT:-${1:-}}"

echo "[prewarm] Fetching/refreshing ArduPilot runtime tree ..."
"$ROOT/scripts/fetch_ardupilot_sitl.sh"

echo "[prewarm] Installing Python SITL dependencies ..."
(cd "$ROOT" && make sitl-deps)

if [[ ! -f "$AP_ROOT/waf" ]]; then
  echo "ArduPilot waf script missing at $AP_ROOT/waf" >&2
  exit 1
fi

echo "[prewarm] Configuring ArduPilot SITL toolchain ..."
(
  cd "$AP_ROOT"
  ./waf configure --board sitl
)

# Prebuild the binaries Guardian launch recipes can hit via current presets.
# ArduBoat typically rides Rover stack/frames, so rover is included.
for target in copter plane rover sub; do
  echo "[prewarm] Building ArduPilot target: $target ..."
  (
    cd "$AP_ROOT"
    ./waf "$target"
  )
done

if [[ -n "$PX4_SRC" ]]; then
  echo "[prewarm] Preparing PX4 SITL from: $PX4_SRC"
  PX4_SRC="$(cd "$PX4_SRC" && pwd)"
  if [[ ! -f "$PX4_SRC/CMakeLists.txt" ]]; then
    echo "Not a PX4-Autopilot root (missing CMakeLists.txt): $PX4_SRC" >&2
    exit 1
  fi

  px4_build_found="0"
  for name in px4_sitl_default px4_macos_default px4_macos_sitl_default; do
    if [[ -x "$PX4_SRC/build/$name/bin/px4" ]] && [[ -d "$PX4_SRC/build/$name/etc" ]]; then
      px4_build_found="1"
      break
    fi
  done

  if [[ "$px4_build_found" != "1" ]]; then
    echo "[prewarm] No PX4 SITL build found, running make px4_sitl_default ..."
    (cd "$PX4_SRC" && make px4_sitl_default)
  else
    echo "[prewarm] Existing PX4 SITL build found."
  fi

  echo "[prewarm] Syncing PX4 SITL bundle into Guardian resources ..."
  PX4_AUTOPILOT_ROOT="$PX4_SRC" "$ROOT/scripts/sync_px4_sitl_bundle.sh"
else
  echo "[prewarm] PX4 skipped (set PX4_AUTOPILOT_ROOT or pass a PX4 path to prewarm/sync PX4 too)."
fi

echo "[prewarm] Done."

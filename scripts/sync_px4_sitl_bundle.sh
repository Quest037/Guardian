#!/usr/bin/env bash
# Copies a **built** PX4 POSIX SITL tree (bin/px4 + etc/ + rootfs) into
# Sources/GuardianHQ/Resources/Px4SitlBundle so SwiftPM bundles it like mavsdk_server.
# This is the install-sized artifact (~tens of MB), not the full PX4-Autopilot source tree.
#
# Prerequisites: PX4-Autopilot already configured with `make px4_sitl_default` (or macOS variant).
#
# Usage:
#   PX4_AUTOPILOT_ROOT=/path/to/PX4-Autopilot ./scripts/sync_px4_sitl_bundle.sh
#   ./scripts/sync_px4_sitl_bundle.sh /path/to/PX4-Autopilot
#
# PX4 is BSD 3-clause — comply with its license when you distribute binaries that include this bundle.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/GuardianHQ/Resources/Px4SitlBundle"
SRC="${PX4_AUTOPILOT_ROOT:-${1:-}}"

if [[ -z "$SRC" ]]; then
  echo "Set PX4_AUTOPILOT_ROOT or pass the PX4-Autopilot repo root as the first argument." >&2
  echo "Example: PX4_AUTOPILOT_ROOT=~/PX4-Autopilot ./scripts/sync_px4_sitl_bundle.sh" >&2
  exit 1
fi

SRC="$(cd "$SRC" && pwd)"
if [[ ! -f "$SRC/CMakeLists.txt" ]]; then
  echo "Not a PX4-Autopilot root (missing CMakeLists.txt): $SRC" >&2
  exit 1
fi

BUILD=""
for name in px4_sitl_default px4_macos_default px4_macos_sitl_default; do
  if [[ -x "$SRC/build/$name/bin/px4" ]] && [[ -d "$SRC/build/$name/etc" ]]; then
    BUILD="$SRC/build/$name"
    break
  fi
done

if [[ -z "$BUILD" ]]; then
  echo "No SITL build found under $SRC/build (looked for px4_sitl_default / px4_macos_* with bin/px4 and etc/)." >&2
  echo "Run: cd \"$SRC\" && make px4_sitl_default" >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/bin" "$DEST/etc"
# Need full bin/: rcS sources px4-alias.sh from PATH, and startup uses px4-* symlinks → px4.
rsync -a "$BUILD/bin/" "$DEST/bin/"
rsync -a "$BUILD/etc/" "$DEST/etc/"

if [[ -d "$BUILD/rootfs" ]]; then
  rm -rf "$DEST/rootfs"
  rsync -a "$BUILD/rootfs/" "$DEST/rootfs/"
else
  mkdir -p "$DEST/rootfs"
fi

(
  cd "$SRC"
  git rev-parse --short HEAD 2>/dev/null || echo "unknown"
) >"$DEST/.guardian_px4_git_rev"

PATCH="$ROOT/Sources/GuardianHQ/Resources/Px4SitlMavlink/px4-rc.mavlink"
if [[ -f "$PATCH" ]]; then
  install -m 644 "$PATCH" "$DEST/etc/init.d-posix/px4-rc.mavlink"
  echo "Installed Guardian px4-rc.mavlink overlay (GUARDIAN_PX4_* port env)."
fi

# Ad-hoc sign main binary (px4-* are symlinks to it). Distribution still needs Developer ID.
if command -v codesign >/dev/null 2>&1; then
  codesign -s - --force "$DEST/bin/px4" 2>/dev/null || true
fi

echo "Synced SITL bundle from $BUILD → $DEST ($(wc -c <"$DEST/bin/px4" | tr -d ' ') bytes px4)"

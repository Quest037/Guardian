#!/usr/bin/env bash
# Stages Gazebo Harmonic (gz-sim) into Sources/GuardianHQ/Resources/GazeboRuntime for SwiftPM bundling.
#
# Prerequisites (pick one):
#   brew install osrf/simulation/gz-harmonic
#   — or set GUARDIAN_GZ_INSTALL_PREFIX to an existing Harmonic prefix.
#
# Usage:
#   ./scripts/fetch_gazebo_runtime.sh
#   GUARDIAN_GZ_INSTALL_PREFIX=/opt/homebrew ./scripts/fetch_gazebo_runtime.sh
#
# Gazebo is Apache 2.0 — comply with its license when distributing binaries in the app bundle.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Sources/GuardianHQ/Resources/GazeboRuntime"
PREFIX="${GUARDIAN_GZ_INSTALL_PREFIX:-${GUARDIAN_GZ_ROOT:-}}"

# Harmonic stack pieces (merged with symlink dereference via rsync -L).
GZ_HARMONIC_FORMULAE=(
  gz-tools2
  gz-sim8
  gz-gui8
  gz-launch7
  gz-sensors8
  gz-rendering8
  gz-physics7
  gz-transport13
  gz-msgs10
  gz-math7
  gz-common5
  gz-utils2
  gz-plugin2
  gz-fuel-tools9
  gz-harmonic
)

resolve_gz_bin() {
  if [[ -n "$PREFIX" && -x "$PREFIX/bin/gz" ]]; then
    echo "$PREFIX/bin/gz"
    return 0
  fi
  if command -v gz >/dev/null 2>&1; then
    command -v gz
    return 0
  fi
  return 1
}

if ! GZ_BIN="$(resolve_gz_bin)"; then
  echo "Gazebo Harmonic not found." >&2
  echo "Install: brew install osrf/simulation/gz-harmonic" >&2
  echo "Or set GUARDIAN_GZ_INSTALL_PREFIX to the install prefix (must contain bin/gz)." >&2
  exit 1
fi

if [[ -z "$PREFIX" ]]; then
  PREFIX="$(cd "$(dirname "$GZ_BIN")/.." && pwd)"
fi
PREFIX="$(cd "$PREFIX" && pwd)"

mkdir -p "$DEST"
rm -rf "$DEST/bin" "$DEST/lib" "$DEST/share"
mkdir -p "$DEST/bin" "$DEST/lib" "$DEST/share"

stage_formula() {
  local formula="$1"
  local p=""
  if ! command -v brew >/dev/null 2>&1; then
    return 0
  fi
  p="$(brew --prefix "$formula" 2>/dev/null || true)"
  [[ -z "$p" || ! -d "$p" ]] && return 0
  if [[ -d "$p/bin" ]]; then
    rsync -aL "$p/bin/" "$DEST/bin/" 2>/dev/null || true
  fi
  if [[ -d "$p/lib" ]]; then
    rsync -aL "$p/lib/" "$DEST/lib/" 2>/dev/null || true
  fi
  if [[ -d "$p/share" ]]; then
    rsync -aL "$p/share/" "$DEST/share/" 2>/dev/null || true
  fi
}

if command -v brew >/dev/null 2>&1; then
  for formula in "${GZ_HARMONIC_FORMULAE[@]}"; do
    stage_formula "$formula"
  done
else
  # Non-Homebrew prefix: copy trees with dereferenced symlinks.
  [[ -d "$PREFIX/bin" ]] && rsync -aL "$PREFIX/bin/" "$DEST/bin/"
  [[ -d "$PREFIX/lib" ]] && rsync -aL "$PREFIX/lib/" "$DEST/lib/"
  [[ -d "$PREFIX/share" ]] && rsync -aL "$PREFIX/share/" "$DEST/share/"
fi

# Ensure `gz` is a real file (not a broken ../Cellar symlink).
if command -v realpath >/dev/null 2>&1; then
  GZ_REAL="$(realpath "$GZ_BIN")"
elif command -v greadlink >/dev/null 2>&1; then
  GZ_REAL="$(greadlink -f "$GZ_BIN")"
else
  GZ_REAL="$GZ_BIN"
fi
cp -fL "$GZ_REAL" "$DEST/bin/gz"
chmod +x "$DEST/bin/gz"

# Keep bundled placeholder worlds (not overwritten by rsync).
mkdir -p "$DEST/worlds"

gz_sim_version="$("$DEST/bin/gz" sim --versions 2>/dev/null | head -n 1 || true)"
echo "${gz_sim_version:-unknown}" >"$DEST/.guardian_gz_sim_version"
if command -v brew >/dev/null 2>&1; then
  brew list --versions gz-harmonic 2>/dev/null | head -n 1 >"$DEST/.guardian_gz_source_rev" || echo "unknown" >"$DEST/.guardian_gz_source_rev"
else
  echo "$("$DEST/bin/gz" --version 2>/dev/null || echo unknown)" >"$DEST/.guardian_gz_source_rev"
fi

STAMP="$DEST/.guardian_gazebo_runtime_built"
date -u +"%Y-%m-%dT%H:%M:%SZ" >"$STAMP"
echo "prefix=$PREFIX" >>"$STAMP"
echo "gz=$(command -v gz 2>/dev/null || echo "$GZ_BIN")" >>"$STAMP"

if command -v codesign >/dev/null 2>&1; then
  while IFS= read -r bin; do
    codesign -s - --force "$bin" 2>/dev/null || true
  done < <(find "$DEST/bin" -maxdepth 1 -type f -perm +111 2>/dev/null || true)
fi

if [[ ! -x "$DEST/bin/gz" ]]; then
  echo "Staged bin/gz is not executable — check Homebrew install." >&2
  exit 1
fi

# World Builder embedded viewport: `gz launch` websocket plugin (optional in Homebrew unless
# libwebsockets was present when gz-launch7 was built).
mkdir -p "$DEST/lib/gz-launch-7/plugins"
WS_PLUGIN=""
while IFS= read -r f; do
  WS_PLUGIN="$f"
  break
done < <(
  find /opt/homebrew/Cellar/gz-launch7 /usr/local/Cellar/gz-launch7 "$PREFIX" \
    -name 'libgz-launch-websocket-server*.dylib' 2>/dev/null || true
)
if [[ -n "$WS_PLUGIN" && -f "$WS_PLUGIN" ]]; then
  cp -fL "$WS_PLUGIN" "$DEST/lib/gz-launch-7/plugins/"
  echo "Staged websocket plugin → $DEST/lib/gz-launch-7/plugins/$(basename "$WS_PLUGIN")"
else
  echo "WARNING: gz-launch-websocket-server not found in this Gazebo install." >&2
  echo "  For World Builder 3D: brew install libwebsockets && brew reinstall gz-launch7, then re-run this script." >&2
fi

echo "Staged Gazebo runtime → $DEST (gz: $(wc -c <"$DEST/bin/gz" | tr -d ' ') bytes)"

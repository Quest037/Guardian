#!/usr/bin/env bash
# Staged colcon build for Guardian's bundled ROS 2 runtime (macOS + RoboStack).
#
# Default (`make build`): stage **minimum** only — px4_msgs + guardian_ros2_vehicle_bridge.
# Optional full stack: GUARDIAN_ROS2_RUNTIME_FULL=1 or `make ros2-runtime-full`
#
# Layout:
#   Ros2Runtime/overlay/install/   colcon merge-install
#   Ros2Runtime/install/setup.bash chains RoboStack underlay + overlay
#
# Prerequisites: make ros2-system-install (RoboStack at ~/.guardian/ros/humble)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$ROOT/Sources/GuardianHQ/Resources/Ros2Runtime"
STACKS="$ROOT/Sources/GuardianHQ/Resources/Ros2AutonomyStacks/upstream"
BRIDGE_PKG="$ROOT/Sources/GuardianHQ/Resources/Ros2VehicleBridge/guardian_ros2_vehicle_bridge"
OVERLAY="$RUNTIME/overlay/install"
CHAIN_SETUP="$RUNTIME/install/setup.bash"
STAMP_FILE="$RUNTIME/.guardian_ros2_runtime_built"
WS="$ROOT/build/ros2_runtime_ws"

CMAKE_EXTRA=(
  -DCMAKE_BUILD_TYPE=Release
  "-DCMAKE_CXX_FLAGS=-Wno-error -Wno-error=deprecated-declarations"
)

want_full() {
  [[ "${GUARDIAN_ROS2_RUNTIME_FULL:-}" == "1" ]] ||
    [[ "${GUARDIAN_ROS2_RUNTIME_AS2:-}" == "1" ]] ||
    [[ "${GUARDIAN_ROS2_RUNTIME_NAV2:-}" == "1" ]]
}

want_as2() {
  [[ "${GUARDIAN_ROS2_SKIP_AS2:-}" == "1" ]] && return 1
  [[ "${GUARDIAN_ROS2_RUNTIME_FULL:-}" == "1" ]] || [[ "${GUARDIAN_ROS2_RUNTIME_AS2:-}" == "1" ]]
}

want_nav2() {
  [[ "${GUARDIAN_ROS2_SKIP_NAV2:-}" == "1" ]] && return 1
  # Default ON for Training Nav2 overlay (set GUARDIAN_ROS2_SKIP_NAV2=1 to skip).
  return 0
}

source_ros() {
  local prefix=""
  prefix="$("$ROOT/scripts/guardian_ros2_system_prefix.sh" 2>/dev/null || true)"
  if [[ -z "$prefix" ]]; then
    for candidate in /opt/ros/humble /opt/ros/jazzy "$HOME/.guardian/ros/humble"; do
      if [[ -f "$candidate/setup.bash" || -f "$candidate/setup.zsh" ]]; then
        prefix="$candidate"
        break
      fi
    done
  fi
  [[ -n "$prefix" ]] || {
    echo "error: ROS 2 not found. Run: make ros2-system-install" >&2
    exit 1
  }
  for setup in setup.bash setup.zsh; do
    if [[ -f "$prefix/$setup" ]]; then
      set +u
      # shellcheck disable=SC1090
      source "$prefix/$setup"
      set -u
      echo "ROS underlay: $prefix (${ROS_DISTRO:-?})"
      export GUARDIAN_ROS_UNDERLAY="$prefix"
      return 0
    fi
  done
  echo "error: no setup script under $prefix" >&2
  exit 1
}

ensure_host_deps() {
  local mamba="${GUARDIAN_MAMBA_EXE:-$HOME/.local/bin/micromamba}"
  local prefix
  prefix="${GUARDIAN_ROS_UNDERLAY:-$("$ROOT/scripts/guardian_ros2_system_prefix.sh" 2>/dev/null || true)}"
  if [[ -x "$mamba" && -n "$prefix" ]]; then
    echo "Ensuring RoboStack packages in $prefix …"
    "$mamba" install -y -p "$prefix" -c conda-forge -c robostack-humble \
      ros-humble-geographic-msgs ros-humble-bond ros-humble-bondcpp \
      ros-humble-ompl ros-humble-behaviortree-cpp-v3 \
      ros-humble-nav2-common ros-humble-nav2-planner ros-humble-nav2-map-server \
      ros-humble-nav2-lifecycle-manager ros-humble-nav2-costmap-2d \
      ros-humble-nav2-navfn-planner ros-humble-nav2-msgs \
      2>/dev/null || true
  fi
  if command -v brew >/dev/null 2>&1; then
    echo "Ensuring Homebrew build deps …"
    brew list geographiclib &>/dev/null || brew install geographiclib
    brew list graphicsmagick &>/dev/null || brew install graphicsmagick
    brew list pkgconf &>/dev/null || brew install pkgconf
    local geolib gm
    geolib="$(brew --prefix geographiclib 2>/dev/null || true)"
    gm="$(brew --prefix graphicsmagick 2>/dev/null || true)"
    [[ -n "$geolib" ]] && export CMAKE_PREFIX_PATH="${geolib}:${CMAKE_PREFIX_PATH:-}"
    [[ -n "$gm" ]] && export CMAKE_PREFIX_PATH="${gm}:${CMAKE_PREFIX_PATH:-}"
    export PKG_CONFIG_PATH="${gm:+$gm/lib/pkgconfig:}${PKG_CONFIG_PATH:-}"
  fi
}

prepare_workspace_links() {
  mkdir -p "$WS/src"
  ln -sfn "$BRIDGE_PKG" "$WS/src/guardian_ros2_vehicle_bridge"
  ln -sfn "$STACKS/px4_msgs" "$WS/src/px4_msgs"
  if want_as2; then
    ln -sfn "$STACKS/aerostack2" "$WS/src/aerostack2"
    ln -sfn "$STACKS/as2_platform_pixhawk" "$WS/src/as2_platform_pixhawk"
  fi
  if want_nav2; then
    ln -sfn "$STACKS/navigation2" "$WS/src/navigation2"
  fi
}

colcon_build() {
  local label="$1"
  shift
  echo ""
  echo "======== colcon: $label ========"
  # shellcheck disable=SC2086
  colcon build \
    --merge-install \
    --install-base "$OVERLAY" \
    --executor sequential \
    --cmake-args "${CMAKE_EXTRA[@]}" \
    "$@"
  echo "======== done: $label ========"
}

stage_minimum() {
  if grep -q '^minimum=' "$STAMP_FILE" 2>/dev/null && [[ "${GUARDIAN_FORCE_ROS2_RUNTIME:-}" != "1" ]]; then
    echo "Stage minimum: already built (stamp). Skipping."
    return 0
  fi
  colcon_build "minimum (px4_msgs + guardian_ros2_vehicle_bridge)" \
    --packages-select px4_msgs guardian_ros2_vehicle_bridge
  touch_stamp minimum
}

stage_as2() {
  want_as2 || return 0
  if grep -q '^as2=' "$STAMP_FILE" 2>/dev/null && [[ "${GUARDIAN_FORCE_ROS2_RUNTIME:-}" != "1" ]]; then
    echo "Stage aerostack2: already built (stamp). Skipping."
    return 0
  fi
  colcon_build "aerostack2 → as2_platform_pixhawk" \
    --packages-up-to as2_platform_pixhawk
  touch_stamp as2
}

stage_nav2() {
  want_nav2 || return 0
  if grep -q '^nav2=' "$STAMP_FILE" 2>/dev/null && [[ "${GUARDIAN_FORCE_ROS2_RUNTIME:-}" != "1" ]]; then
    echo "Stage nav2: already built (stamp). Skipping."
    return 0
  fi
  colcon_build "navigation2 → nav2_bringup" \
    --packages-up-to nav2_bringup \
    --packages-ignore nav2_system_tests
  touch_stamp nav2
}

touch_stamp() {
  local key="$1"
  mkdir -p "$RUNTIME"
  grep -v "^${key}=" "$STAMP_FILE" 2>/dev/null >"${STAMP_FILE}.tmp" || true
  echo "${key}=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"${STAMP_FILE}.tmp"
  mv "${STAMP_FILE}.tmp" "$STAMP_FILE"
}

write_chain_setup() {
  local underlay="${GUARDIAN_ROS_UNDERLAY:-$("$ROOT/scripts/guardian_ros2_system_prefix.sh")}"
  mkdir -p "$RUNTIME/install" "$RUNTIME/overlay"
  cat >"$CHAIN_SETUP" <<SETUP
# Generated by scripts/build_ros2_runtime_bundle.sh — chains RoboStack + Guardian overlay.
# Re-run: make ros2-runtime
_GUARDIAN_ROS_UNDERLAY="$underlay"
_OVERLAY_ROOT="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
set +u
if [[ -f "\$_GUARDIAN_ROS_UNDERLAY/setup.bash" ]]; then
  source "\$_GUARDIAN_ROS_UNDERLAY/setup.bash"
elif [[ -f "\$_GUARDIAN_ROS_UNDERLAY/setup.zsh" ]]; then
  source "\$_GUARDIAN_ROS_UNDERLAY/setup.zsh"
fi
if [[ -f "\$_OVERLAY_ROOT/overlay/install/setup.bash" ]] && [[ ! -L "\$_OVERLAY_ROOT/overlay/install/setup.bash" ]]; then
  source "\$_OVERLAY_ROOT/overlay/install/setup.bash"
elif [[ -f "\$_OVERLAY_ROOT/overlay/install/local_setup.bash" ]]; then
  source "\$_OVERLAY_ROOT/overlay/install/local_setup.bash"
fi
set -u
SETUP
  # Remove bad symlink if a previous script revision created one.
  if [[ -L "$OVERLAY/setup.bash" ]]; then
    rm -f "$OVERLAY/setup.bash"
  fi
  test -f "$CHAIN_SETUP"
  [[ -f "$OVERLAY/local_setup.bash" || ( -f "$OVERLAY/setup.bash" && ! -L "$OVERLAY/setup.bash" ) ]] || {
    echo "error: colcon did not produce overlay local_setup.bash" >&2
    exit 1
  }
}

verify_overlay() {
  [[ -d "$OVERLAY/share/guardian_ros2_vehicle_bridge" ]] || {
    echo "error: guardian_ros2_vehicle_bridge not in overlay install" >&2
    exit 1
  }
  bash -lc "set +u; source \"$CHAIN_SETUP\"; set -u; command -v ros2; ros2 pkg prefix guardian_ros2_vehicle_bridge" \
    || {
      echo "error: chained setup failed (ros2 or guardian_ros2_vehicle_bridge not on PATH)" >&2
      exit 1
    }
  echo "Verified: ros2 + guardian_ros2_vehicle_bridge package OK."
}

chain_setup_works() {
  [[ -d "$OVERLAY/share/guardian_ros2_vehicle_bridge" ]] || return 1
  bash -lc "set +u; source \"$CHAIN_SETUP\"; set -u; ros2 pkg prefix guardian_ros2_vehicle_bridge" &>/dev/null
}

nav2_available_in_env() {
  bash -lc "set +u; source \"$CHAIN_SETUP\"; set -u; ros2 pkg prefix nav2_planner" &>/dev/null
}

maybe_skip_all() {
  if [[ "${GUARDIAN_FORCE_ROS2_RUNTIME:-}" == "1" ]]; then
    return 1
  fi
  [[ -f "$CHAIN_SETUP" ]] || return 1
  grep -q '^minimum=' "$STAMP_FILE" 2>/dev/null || return 1
  if want_as2 && ! grep -q '^as2=' "$STAMP_FILE" 2>/dev/null; then return 1; fi
  if want_nav2 && ! grep -q '^nav2=' "$STAMP_FILE" 2>/dev/null; then return 1; fi
  chain_setup_works || return 1
  echo "Ros2Runtime up to date ($STAMP_FILE)."
  return 0
}

main() {
  if maybe_skip_all; then
    exit 0
  fi
  # Reuse overlay from a prior minimum build when only the chain script was broken.
  if grep -q '^minimum=' "$STAMP_FILE" 2>/dev/null \
    && [[ -d "$OVERLAY/share/guardian_ros2_vehicle_bridge" ]] \
    && [[ "${GUARDIAN_FORCE_ROS2_RUNTIME:-}" != "1" ]]; then
    echo "Reusing existing overlay; refreshing chain setup only."
    write_chain_setup
    verify_overlay
    exit 0
  fi

  "$ROOT/scripts/fetch_ros2_autonomy_stacks.sh"
  for dir in px4_msgs; do
    [[ -d "$STACKS/$dir" ]] || {
      echo "missing $STACKS/$dir" >&2
      exit 1
    }
  done
  if want_as2; then
    for dir in aerostack2 as2_platform_pixhawk; do
      [[ -d "$STACKS/$dir" ]] || {
        echo "missing $STACKS/$dir" >&2
        exit 1
      }
    done
  fi
  if want_nav2; then
    [[ -d "$STACKS/navigation2" ]] || {
      echo "missing $STACKS/navigation2" >&2
      exit 1
    }
  fi

  source_ros
  ensure_host_deps
  mkdir -p "$OVERLAY" "$WS/src"
  prepare_workspace_links

  # Always build minimum; Nav2 for Training (RoboStack underlay and/or colcon overlay).
  stage_minimum
  write_chain_setup
  if want_nav2; then
    if nav2_available_in_env; then
      echo "Nav2 planner packages available from ROS underlay (RoboStack)."
      touch_stamp nav2
    else
      echo "Nav2 not in underlay; colcon-building navigation2 (slow) …"
      stage_nav2
    fi
  fi
  if want_full; then
    stage_as2
    if ! grep -q '^nav2=' "$STAMP_FILE" 2>/dev/null; then
      stage_nav2
    fi
  fi

  write_chain_setup
  verify_overlay
  "$ROOT/scripts/fetch_micro_xrce_agent.sh" || echo "warning: MicroXRCEAgent not bundled." >&2
  echo "ros_distro=${ROS_DISTRO:-humble}" >"$STAMP_FILE.meta"
  echo "Ros2Runtime ready: $CHAIN_SETUP"
}

main

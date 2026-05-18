#!/usr/bin/env bash
# Install ROS 2 Humble for Guardian using RoboStack (prebuilt macOS ARM64).
#
# Default install prefix (no sudo):
#   ~/.guardian/ros/humble
#
# System-wide (requires sudo password):
#   GUARDIAN_ROS2_USE_OPT=1 ./scripts/install_ros2_macos.sh
#   → /opt/ros/humble
#
# Usage:
#   ./scripts/install_ros2_macos.sh
# Then: make build

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${GUARDIAN_ROS2_USE_OPT:-}" == "1" ]]; then
  INSTALL_PREFIX="/opt/ros/humble"
else
  INSTALL_PREFIX="${GUARDIAN_ROS2_PREFIX:-$HOME/.guardian/ros/humble}"
fi

MAMBA_ROOT="${GUARDIAN_MAMBA_ROOT:-$HOME/micromamba}"
MAMBA_EXE="${GUARDIAN_MAMBA_EXE:-$HOME/.local/bin/micromamba}"
if [[ ! -x "$MAMBA_EXE" ]] && [[ -x "$MAMBA_ROOT/bin/micromamba" ]]; then
  MAMBA_EXE="$MAMBA_ROOT/bin/micromamba"
fi

install_micromamba() {
  if [[ -x "$MAMBA_EXE" ]]; then
    echo "micromamba: $MAMBA_EXE"
    return 0
  fi
  echo "Installing micromamba …"
  curl -Ls https://micro.mamba.pm/install.sh | bash -s -- -b -p "$MAMBA_ROOT"
  MAMBA_EXE="$HOME/.local/bin/micromamba"
  if [[ ! -x "$MAMBA_EXE" ]] && [[ -x "$MAMBA_ROOT/bin/micromamba" ]]; then
    MAMBA_EXE="$MAMBA_ROOT/bin/micromamba"
  fi
  [[ -x "$MAMBA_EXE" ]] || { echo "error: micromamba not found after install" >&2; exit 1; }
}

verify_install() {
  local setup=""
  if [[ -f "$INSTALL_PREFIX/setup.bash" ]]; then
    setup="$INSTALL_PREFIX/setup.bash"
  elif [[ -f "$INSTALL_PREFIX/setup.zsh" ]]; then
    setup="$INSTALL_PREFIX/setup.zsh"
  else
    echo "error: no setup script under $INSTALL_PREFIX" >&2
    exit 1
  fi
  bash -lc "set +u; source \"\$1\"; set -u; command -v ros2 && command -v colcon" _ "$setup" \
    || { echo "error: ros2/colcon not available after sourcing $setup" >&2; exit 1; }
  echo "ROS 2 OK at $INSTALL_PREFIX"
  echo "  ros2: $INSTALL_PREFIX/bin/ros2"
  echo "  colcon: $($INSTALL_PREFIX/bin/colcon --version 2>/dev/null | head -1)"
}

maybe_skip() {
  if [[ "${GUARDIAN_FORCE_ROS2_INSTALL:-}" == "1" ]]; then
    return 1
  fi
  if [[ -f "$INSTALL_PREFIX/setup.bash" || -f "$INSTALL_PREFIX/setup.zsh" ]]; then
    if [[ -x "$INSTALL_PREFIX/bin/ros2" ]] || command -v "$INSTALL_PREFIX/bin/ros2" >/dev/null 2>&1; then
      echo "ROS 2 already at $INSTALL_PREFIX"
      verify_install
      exit 0
    fi
  fi
  return 1
}

write_prefix_marker() {
  mkdir -p "$ROOT/.guardian"
  printf '%s\n' "$INSTALL_PREFIX" >"$ROOT/.guardian/ros2_system_prefix"
}

main() {
  if maybe_skip; then
    write_prefix_marker
    exit 0
  fi

  install_micromamba
  export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$MAMBA_ROOT}"

  mkdir -p "$(dirname "$INSTALL_PREFIX")"
  if [[ "$INSTALL_PREFIX" == /opt/ros/* ]]; then
    echo "Installing to $INSTALL_PREFIX (sudo) …"
    sudo mkdir -p /opt/ros
    sudo "$MAMBA_EXE" create -y -p "$INSTALL_PREFIX" \
      -c conda-forge -c robostack-humble \
      ros-humble-desktop ros-dev-tools colcon-common-extensions python=3.11
    sudo chown -R "$(whoami)" "$INSTALL_PREFIX"
  else
    echo "Installing to $INSTALL_PREFIX …"
    if [[ ! -d "$INSTALL_PREFIX/bin" ]]; then
      "$MAMBA_EXE" create -y -p "$INSTALL_PREFIX" \
        -c conda-forge -c robostack-humble \
        ros-humble-desktop ros-dev-tools colcon-common-extensions \
        ros-humble-geographic-msgs python=3.11
    else
      "$MAMBA_EXE" install -y -p "$INSTALL_PREFIX" \
        -c conda-forge -c robostack-humble \
        ros-humble-geographic-msgs ros-humble-bond ros-humble-bondcpp \
        ros-humble-ompl ros-humble-behaviortree-cpp-v3
    fi
  fi

  if [[ ! -f "$INSTALL_PREFIX/setup.bash" ]] && [[ -f "$INSTALL_PREFIX/setup.zsh" ]]; then
    ln -sf setup.zsh "$INSTALL_PREFIX/setup.bash"
  fi

  write_prefix_marker
  verify_install
  echo ""
  echo "Installed: $INSTALL_PREFIX"
  echo "Optional shell: source $INSTALL_PREFIX/setup.bash"
  echo "Next: cd $ROOT && make build"
  if [[ "$INSTALL_PREFIX" != "/opt/ros/humble" ]]; then
    echo ""
    echo "For /opt/ros/humble instead: GUARDIAN_ROS2_USE_OPT=1 ./scripts/install_ros2_macos.sh"
  fi
}

main

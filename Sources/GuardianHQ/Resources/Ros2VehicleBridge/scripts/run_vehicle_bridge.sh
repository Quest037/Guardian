#!/usr/bin/env bash
# Dev helper: run the Guardian ROS 2 vehicle bridge from a colcon workspace or source tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="${ROOT}/guardian_ros2_vehicle_bridge"
CONFIG="${GUARDIAN_ROS2_BRIDGE_CONFIG:-${PKG_DIR}/config/vehicles.example.yaml}"

if [[ -f "${ROOT}/install/setup.bash" ]]; then
  # shellcheck source=/dev/null
  source "${ROOT}/install/setup.bash"
elif [[ -n "${ROS_DISTRO:-}" ]]; then
  :
else
  echo "Source ROS 2 (e.g. source /opt/ros/jazzy/setup.bash) or build this package with colcon first." >&2
  exit 1
fi

export GUARDIAN_ROS2_BRIDGE_CONFIG="${CONFIG}"
exec ros2 run guardian_ros2_vehicle_bridge guardian_ros2_vehicle_bridge --config "${CONFIG}"

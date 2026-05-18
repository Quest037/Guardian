#!/usr/bin/env bash
# Prints the ROS 2 system prefix Guardian should source (one line, no trailing slash).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${GUARDIAN_ROS2_PREFIX:-}" ]]; then
  echo "${GUARDIAN_ROS2_PREFIX%/}"
  exit 0
fi
if [[ -f "$ROOT/.guardian/ros2_system_prefix" ]]; then
  sed -n '1p' "$ROOT/.guardian/ros2_system_prefix"
  exit 0
fi
for candidate in /opt/ros/humble /opt/ros/jazzy "$HOME/.guardian/ros/humble"; do
  if [[ -f "$candidate/setup.bash" || -f "$candidate/setup.zsh" ]]; then
    echo "$candidate"
    exit 0
  fi
done
exit 1

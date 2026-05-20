"""Detect when the Guardian Training Nav2 stack can accept path plans (Humble+ action API)."""

from __future__ import annotations

import subprocess

# Nav2 planner_server exposes ``ComputePathToPose`` as an **action** (not a service) on Humble.
TRAINING_COMPUTE_PATH_ACTION_CANDIDATES = (
    "/compute_path_to_pose",
    "/planner_server/compute_path_to_pose",
)

# Legacy service names (older Nav2 / forks); kept for readiness probes only.
TRAINING_COMPUTE_PATH_SERVICE_CANDIDATES = (
    "/planner_server/compute_path_to_pose",
    "/compute_path_to_pose",
)


def training_planner_planning_available(*, env: dict[str, str], list_timeout_s: float = 8.0) -> bool:
    """True when ``compute_path_to_pose`` action (or legacy service) is visible in the graph."""
    try:
        action_result = subprocess.run(
            ["ros2", "action", "list"],
            capture_output=True,
            text=True,
            timeout=list_timeout_s,
            env=env,
        )
        if action_result.returncode == 0:
            action_lines = {line.strip() for line in action_result.stdout.splitlines()}
            if any(name in action_lines for name in TRAINING_COMPUTE_PATH_ACTION_CANDIDATES):
                return True
    except (OSError, subprocess.TimeoutExpired):
        pass

    try:
        service_result = subprocess.run(
            ["ros2", "service", "list"],
            capture_output=True,
            text=True,
            timeout=list_timeout_s,
            env=env,
        )
        if service_result.returncode == 0:
            service_lines = {line.strip() for line in service_result.stdout.splitlines()}
            return any(name in service_lines for name in TRAINING_COMPUTE_PATH_SERVICE_CANDIDATES)
    except (OSError, subprocess.TimeoutExpired):
        pass

    return False

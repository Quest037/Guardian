"""Tests for Nav2 planner readiness (action API on Humble)."""

from unittest.mock import patch

from guardian_ros2_vehicle_bridge.nav2_planner_availability import (
    training_planner_planning_available,
)


def test_training_planner_planning_available_detects_action() -> None:
    def fake_run(cmd, **kwargs):
        class Result:
            returncode = 0
            stdout = "/compute_path_to_pose\n/is_path_valid\n"

        return Result()

    with patch(
        "guardian_ros2_vehicle_bridge.nav2_planner_availability.subprocess.run",
        side_effect=fake_run,
    ):
        assert training_planner_planning_available(env={}) is True


def test_training_planner_planning_available_false_when_missing() -> None:
    def fake_run(cmd, **kwargs):
        class Result:
            returncode = 0
            stdout = "/is_path_valid\n"

        return Result()

    with patch(
        "guardian_ros2_vehicle_bridge.nav2_planner_availability.subprocess.run",
        side_effect=fake_run,
    ):
        assert training_planner_planning_available(env={}) is False

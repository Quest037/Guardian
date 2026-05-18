"""Tests for Training Nav2 namespace routing and stack health."""

from guardian_ros2_vehicle_bridge.nav2_training_stack import (
    Nav2TrainingStack,
    training_plan_namespace,
)


def test_training_plan_namespace_is_global() -> None:
    assert training_plan_namespace("") == ""
    assert training_plan_namespace("px4_1") == ""


def test_health_snapshot_when_stopped() -> None:
    stack = Nav2TrainingStack.shared()
    stack.force_stop()
    health = stack.health_snapshot()
    assert health["training_stack"] == "nav2_minimal"
    assert health["ready"] is False
    assert health["starting"] is False

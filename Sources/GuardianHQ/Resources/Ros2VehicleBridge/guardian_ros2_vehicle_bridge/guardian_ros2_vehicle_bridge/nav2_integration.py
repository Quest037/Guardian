"""
Nav2 integration for UGV / USV (Training open-field stack + future navigate_to_pose).

Guardian starts a minimal global Nav2 stack (``nav2_training.launch.py``) when any
enabled vehicle uses the Nav2 planner kind. Training path overlay calls
``/planner_server/compute_path_to_pose`` on that stack.
"""

from __future__ import annotations

from dataclasses import dataclass

from guardian_ros2_vehicle_bridge.nav2_training_stack import Nav2TrainingStack
from guardian_ros2_vehicle_bridge.vehicle_config import VehicleConnectionConfig


@dataclass(frozen=True)
class Nav2PlannerRoots:
    """Relative ROS graph roots Guardian will use when Nav2 is fully integrated."""

    navigate_to_pose_action: str = "navigate_to_pose"
    goal_pose_topic: str = "goal_pose"
    planner_server: str = "planner_server"
    controller_server: str = "controller_server"
    bt_navigator: str = "bt_navigator"


class Nav2PlannerBridge:
    """Per-vehicle Nav2 registration (Training uses shared open-field planner)."""

    def __init__(self, config: VehicleConnectionConfig) -> None:
        self._config = config
        self._roots = Nav2PlannerRoots()

    @property
    def vehicle_id(self) -> str:
        return self._config.vehicle_id

    def topic_fqn(self, relative: str) -> str:
        return self._config.topic_fqn(relative)

    def expected_graph_topics(self) -> list[str]:
        return [self.topic_fqn(self._roots.goal_pose_topic)]

    def health_snapshot(self) -> dict[str, object]:
        stack = Nav2TrainingStack.shared().health_snapshot()
        ready = bool(stack.get("ready"))
        starting = bool(stack.get("starting"))
        status = "READY" if ready else ("STARTING" if starting else "LAZY")
        detail: dict[str, object] = {
            "planner": "nav2",
            "vehicle_id": self.vehicle_id,
            "status": status,
            "training_stack": stack,
            "expected_topics": self.expected_graph_topics(),
            "note": "Training overlay uses global open-field planner_server",
        }
        detail.update(self._config.brain_overlay_detail())
        return detail

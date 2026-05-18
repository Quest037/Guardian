"""
Aerostack2 integration stub (UAV aerial planning and control framework).

Guardian product lock: **Aerostack2** is the default ROS 2 planner/control stack for UAV classes
(multicopter, fixed-wing, VTOL). Mission pipelines, motion references, and Aerostack2 modules are
not wired yet — this module only declares expected namespace roots for discovery.

See ``README_AUTONOMY.md``.
"""

from __future__ import annotations

from dataclasses import dataclass

from guardian_ros2_vehicle_bridge.vehicle_config import VehicleConnectionConfig


@dataclass(frozen=True)
class Aerostack2PlannerRoots:
    """Relative roots under the vehicle namespace for future Aerostack2 graphs."""

    motion_reference_topic: str = "motion_reference"
    mission_topic: str = "mission"
    platform_info_topic: str = "platform/info"


class Aerostack2PlannerBridge:
    """Per-vehicle Aerostack2 sidecar stub (no missions or setpoints yet)."""

    def __init__(self, config: VehicleConnectionConfig) -> None:
        self._config = config
        self._roots = Aerostack2PlannerRoots()

    @property
    def vehicle_id(self) -> str:
        return self._config.vehicle_id

    def topic_fqn(self, relative: str) -> str:
        return self._config.topic_fqn(relative)

    def expected_graph_topics(self) -> list[str]:
        return [
            self.topic_fqn(self._roots.motion_reference_topic),
        ]

    def health_snapshot(self) -> dict[str, object]:
        return {
            "planner": "aerostack2",
            "vehicle_id": self.vehicle_id,
            "status": "STUB",
            "expected_topics": self.expected_graph_topics(),
            "note": "Aerostack2 mission and motion-reference wiring not implemented",
        }

"""Tracks active per-vehicle ROS 2 nodes for add/remove teardown (parallel to MAVSDK system-id workers)."""

from __future__ import annotations

from typing import TYPE_CHECKING

from guardian_ros2_vehicle_bridge.vehicle_config import VehicleConnectionConfig

if TYPE_CHECKING:
    from guardian_ros2_vehicle_bridge.px4_vehicle_node import Px4VehicleConnectionNode


class VehicleConnectionRegistry:
    def __init__(self) -> None:
        self._nodes: dict[str, Px4VehicleConnectionNode] = {}

    def keys(self) -> list[str]:
        return sorted(self._nodes.keys())

    def get(self, vehicle_id: str) -> Px4VehicleConnectionNode | None:
        return self._nodes.get(vehicle_id)

    def reconcile(
        self,
        desired: list[VehicleConnectionConfig],
        node_factory,
        executor=None,
    ) -> None:
        desired_ids = {c.vehicle_id for c in desired if c.enabled}
        for vid in list(self._nodes.keys()):
            if vid not in desired_ids:
                self._drop_node(vid, executor)
        config_by_id = {c.vehicle_id: c for c in desired if c.enabled}
        for vid in sorted(desired_ids):
            cfg = config_by_id[vid]
            existing = self._nodes.get(vid)
            if existing is not None and existing.matches_config(cfg):
                continue
            if existing is not None:
                self._drop_node(vid, executor)
            self._nodes[vid] = node_factory(cfg)

    def _drop_node(self, vehicle_id: str, executor=None) -> None:
        node = self._nodes.pop(vehicle_id, None)
        if node is None:
            return
        if executor is not None:
            executor.remove_node(node)
        node.destroy_node()

    def destroy_all(self, executor=None) -> None:
        for vid in list(self._nodes.keys()):
            self._drop_node(vid, executor)

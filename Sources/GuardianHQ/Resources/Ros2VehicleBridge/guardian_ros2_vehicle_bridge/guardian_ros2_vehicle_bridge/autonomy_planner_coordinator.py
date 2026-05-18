"""Registers Nav2 / Aerostack2 planner bridges per PX4 vehicle connection."""

from __future__ import annotations

from guardian_ros2_vehicle_bridge.aerostack2_integration import Aerostack2PlannerBridge
from guardian_ros2_vehicle_bridge.autonomy_planner_kind import (
    AutonomyPlannerKind,
    default_planner_for_class,
    parse_planner_kind,
)
from guardian_ros2_vehicle_bridge.json_emit import emit_vehicle
from guardian_ros2_vehicle_bridge.nav2_integration import Nav2PlannerBridge
from guardian_ros2_vehicle_bridge.vehicle_config import VehicleConnectionConfig


class AutonomyPlannerCoordinator:
    def __init__(self) -> None:
        self._nav2: dict[str, Nav2PlannerBridge] = {}
        self._aerostack2: dict[str, Aerostack2PlannerBridge] = {}

    def reconcile(self, vehicles: list[VehicleConnectionConfig]) -> None:
        desired = {v.vehicle_id: v for v in vehicles if v.enabled}
        for vid in list(self._nav2.keys()):
            if vid not in desired:
                del self._nav2[vid]
        for vid in list(self._aerostack2.keys()):
            if vid not in desired:
                del self._aerostack2[vid]

        wants_nav2_training = False
        for cfg in desired.values():
            kind = self._planner_kind(cfg)
            self._drop_vehicle(cfg.vehicle_id)
            if kind is AutonomyPlannerKind.NAV2:
                wants_nav2_training = True
                bridge = Nav2PlannerBridge(cfg)
                self._nav2[cfg.vehicle_id] = bridge
                self._emit_registered(cfg.vehicle_id, kind, bridge.health_snapshot())
            elif kind is AutonomyPlannerKind.AEROSTACK2:
                bridge = Aerostack2PlannerBridge(cfg)
                self._aerostack2[cfg.vehicle_id] = bridge
                self._emit_registered(cfg.vehicle_id, kind, bridge.health_snapshot())
            else:
                self._emit_registered(cfg.vehicle_id, kind, {"status": "NONE"})

        if wants_nav2_training:
            from guardian_ros2_vehicle_bridge.nav2_training_stack import Nav2TrainingStack

            Nav2TrainingStack.shared().ensure_running_async()

    def _planner_kind(self, cfg: VehicleConnectionConfig) -> AutonomyPlannerKind:
        if cfg.autonomy_planner:
            return parse_planner_kind(cfg.autonomy_planner)
        return default_planner_for_class(cfg.vehicle_class)

    def _drop_vehicle(self, vehicle_id: str) -> None:
        self._nav2.pop(vehicle_id, None)
        self._aerostack2.pop(vehicle_id, None)

    def _emit_registered(self, vehicle_id: str, kind: AutonomyPlannerKind, detail: dict) -> None:
        emit_vehicle(
            vehicle_id,
            {
                "type": "ros2_autonomy_planner",
                "planner": kind.value,
                "detail": detail,
            },
        )

    def destroy_all(self) -> None:
        from guardian_ros2_vehicle_bridge.nav2_training_stack import Nav2TrainingStack

        Nav2TrainingStack.shared().force_stop()
        self._nav2.clear()
        self._aerostack2.clear()

"""Guardian autonomy planner selection (Nav2 vs Aerostack2)."""

from __future__ import annotations

from enum import Enum

from guardian_ros2_vehicle_bridge.vehicle_config import FleetVehicleClass


class AutonomyPlannerKind(str, Enum):
    NONE = "none"
    NAV2 = "nav2"
    AEROSTACK2 = "aerostack2"


def default_planner_for_class(vehicle_class: FleetVehicleClass) -> AutonomyPlannerKind:
    """Product lock: UGV + USV → Nav2; UAV → Aerostack2; UUV/unknown → none."""
    if vehicle_class in (
        FleetVehicleClass.UGV_WHEELED,
        FleetVehicleClass.UGV_TRACKED,
        FleetVehicleClass.UGV_LEGGED,
        FleetVehicleClass.USV,
    ):
        return AutonomyPlannerKind.NAV2
    if vehicle_class in (
        FleetVehicleClass.UAV_COPTER,
        FleetVehicleClass.UAV_FIXED_WING,
        FleetVehicleClass.UAV_VTOL,
    ):
        return AutonomyPlannerKind.AEROSTACK2
    return AutonomyPlannerKind.NONE


def parse_planner_kind(raw: str | None) -> AutonomyPlannerKind:
    if raw is None or not str(raw).strip():
        return AutonomyPlannerKind.NONE
    key = str(raw).strip().lower()
    for member in AutonomyPlannerKind:
        if member.value == key:
            return member
    return AutonomyPlannerKind.NONE

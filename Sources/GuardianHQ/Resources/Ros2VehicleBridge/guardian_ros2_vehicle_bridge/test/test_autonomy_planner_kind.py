from guardian_ros2_vehicle_bridge.autonomy_planner_kind import (
    AutonomyPlannerKind,
    default_planner_for_class,
)
from guardian_ros2_vehicle_bridge.vehicle_config import FleetVehicleClass


def test_ugv_nav2():
    assert default_planner_for_class(FleetVehicleClass.UGV_WHEELED) == AutonomyPlannerKind.NAV2


def test_uav_aerostack2():
    assert default_planner_for_class(FleetVehicleClass.UAV_COPTER) == AutonomyPlannerKind.AEROSTACK2


def test_uuv_none():
    assert default_planner_for_class(FleetVehicleClass.UUV) == AutonomyPlannerKind.NONE

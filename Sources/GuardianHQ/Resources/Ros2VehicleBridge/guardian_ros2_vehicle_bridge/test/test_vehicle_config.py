import pytest

from guardian_ros2_vehicle_bridge.vehicle_config import (
    AutopilotStack,
    BridgeConfig,
    FleetVehicleClass,
    VehicleConnectionConfig,
    ros_safe_node_name_suffix,
)


def test_ros_safe_node_name_suffix_sysid_colon():
    assert ros_safe_node_name_suffix("sysid:147") == "sysid_147"


def test_topic_fqn_with_namespace():
    cfg = VehicleConnectionConfig(
        vehicle_id="v1",
        ros_namespace="px4_0",
    )
    assert cfg.topic_fqn("fmu/out/vehicle_status") == "/px4_0/fmu/out/vehicle_status"


def test_topic_fqn_default_namespace():
    cfg = VehicleConnectionConfig(vehicle_id="v1")
    assert cfg.topic_fqn("fmu/out/vehicle_status") == "/fmu/out/vehicle_status"


def test_vehicle_class_aliases():
    assert FleetVehicleClass.from_config_value("UAV-C") == FleetVehicleClass.UAV_COPTER
    assert FleetVehicleClass.from_config_value("ugv-w") == FleetVehicleClass.UGV_WHEELED


def test_ardupilot_stack_rejected():
    with pytest.raises(ValueError, match="not implemented"):
        VehicleConnectionConfig.from_mapping(
            {"vehicle_id": "a", "stack": "ardupilot"},
        )


def test_bridge_config_from_mapping():
    cfg = BridgeConfig.from_mapping(
        {
            "vehicles": [
                {
                    "vehicle_id": "sim1",
                    "stack": "px4",
                    "vehicle_class": "uav_vtol",
                    "enabled": True,
                }
            ],
            "timing": {"stale_topic_s": 3.0},
        }
    )
    assert len(cfg.enabled_vehicles()) == 1
    assert cfg.enabled_vehicles()[0].stack == AutopilotStack.PX4
    assert cfg.enabled_vehicles()[0].vehicle_class == FleetVehicleClass.UAV_VTOL
    assert cfg.stale_topic_s == 3.0

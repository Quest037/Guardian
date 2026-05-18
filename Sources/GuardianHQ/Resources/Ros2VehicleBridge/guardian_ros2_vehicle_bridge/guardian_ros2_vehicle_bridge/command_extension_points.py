"""
Future PX4 command / setpoint publishers (stubs only).

MAVSDK (``mavsdk_bridge.py``) remains the primary path for arming, mode changes, mission
upload, and general vehicle management. This ROS 2 bridge is for PX4-specific ROS 2 / uORB
access and future autonomy stacks (Nav2, Aerostack2, offboard setpoints) — do not send
movement or offboard commands from here until dedicated plugins exist.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from guardian_ros2_vehicle_bridge.vehicle_config import FleetVehicleClass, VehicleConnectionConfig


class Px4CommandPublisherStub(ABC):
    """Base stub for per-class PX4 command publishers."""

    def __init__(self, config: VehicleConnectionConfig) -> None:
        self._config = config

    @property
    def vehicle_id(self) -> str:
        return self._config.vehicle_id

    @abstractmethod
    def topic_roots(self) -> list[str]:
        """Relative ``fmu/in/...`` roots this plugin would use when implemented."""


class Px4MulticopterOffboardSetpoints(Px4CommandPublisherStub):
    # TODO: ``fmu/in/trajectory_setpoint``, offboard mode guards — multicopter / UAV-C.

    def topic_roots(self) -> list[str]:
        return ["fmu/in/trajectory_setpoint", "fmu/in/offboard_control_mode"]


class Px4FixedWingSetpoints(Px4CommandPublisherStub):
    # TODO: fixed-wing trajectory / attitude setpoints — UAV-F.

    def topic_roots(self) -> list[str]:
        return ["fmu/in/trajectory_setpoint"]


class Px4VtolSetpoints(Px4CommandPublisherStub):
    # TODO: VTOL transition-aware setpoints — UAV-V.

    def topic_roots(self) -> list[str]:
        return ["fmu/in/trajectory_setpoint", "fmu/in/vehicle_command"]


class Px4RoverUgvSetpoints(Px4CommandPublisherStub):
    # TODO: rover / UGV wheel & tracked setpoints — UGV-W, UGV-T, UGV-L.

    def topic_roots(self) -> list[str]:
        return ["fmu/in/trajectory_setpoint"]


class Px4UsvUuvSetpoints(Px4CommandPublisherStub):
    # TODO: marine surface / underwater setpoints when PX4 airframe supports apply — USV, UUV.

    def topic_roots(self) -> list[str]:
        return ["fmu/in/trajectory_setpoint"]


def command_stub_for_class(config: VehicleConnectionConfig) -> Px4CommandPublisherStub:
    """Return the placeholder publisher for a vehicle class (not wired to rclpy yet)."""
    match config.vehicle_class:
        case FleetVehicleClass.UAV_COPTER:
            return Px4MulticopterOffboardSetpoints(config)
        case FleetVehicleClass.UAV_FIXED_WING:
            return Px4FixedWingSetpoints(config)
        case FleetVehicleClass.UAV_VTOL:
            return Px4VtolSetpoints(config)
        case FleetVehicleClass.UGV_WHEELED | FleetVehicleClass.UGV_TRACKED | FleetVehicleClass.UGV_LEGGED:
            return Px4RoverUgvSetpoints(config)
        case FleetVehicleClass.USV | FleetVehicleClass.UUV:
            return Px4UsvUuvSetpoints(config)
        case _:
            return Px4MulticopterOffboardSetpoints(config)

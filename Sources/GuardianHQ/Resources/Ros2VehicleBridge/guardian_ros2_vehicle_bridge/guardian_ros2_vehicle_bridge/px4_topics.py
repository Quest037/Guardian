"""PX4 uXRCE-DDS ROS 2 topic names (output / status only — no command topics yet)."""

from __future__ import annotations

from dataclasses import dataclass

# Relative paths under the vehicle ROS namespace (see PX4 ROS 2 user guide / px4_ros_com).
PX4_FMU_OUT_PREFIX = "fmu/out"

PX4_BASIC_OUTPUT_TOPICS: dict[str, str] = {
    "vehicle_status": f"{PX4_FMU_OUT_PREFIX}/vehicle_status",
    "vehicle_local_position": f"{PX4_FMU_OUT_PREFIX}/vehicle_local_position",
    "vehicle_global_position": f"{PX4_FMU_OUT_PREFIX}/vehicle_global_position",
    "battery_status": f"{PX4_FMU_OUT_PREFIX}/battery_status",
    "vehicle_odometry": f"{PX4_FMU_OUT_PREFIX}/vehicle_odometry",
}

# px4_msgs type names as advertised on the wire (for discovery verification).
PX4_BASIC_OUTPUT_TYPES: dict[str, str] = {
    "vehicle_status": "px4_msgs/msg/VehicleStatus",
    "vehicle_local_position": "px4_msgs/msg/VehicleLocalPosition",
    "vehicle_global_position": "px4_msgs/msg/VehicleGlobalPosition",
    "battery_status": "px4_msgs/msg/BatteryStatus",
    "vehicle_odometry": "px4_msgs/msg/VehicleOdometry",
}


@dataclass(frozen=True)
class TopicDiscoveryResult:
    expected: dict[str, str]
    present: dict[str, bool]
    advertised_types: dict[str, list[str]]

    @property
    def all_present(self) -> bool:
        return bool(self.expected) and all(self.present.values())

    @property
    def any_present(self) -> bool:
        return any(self.present.values())

    def missing_keys(self) -> list[str]:
        return [k for k, ok in self.present.items() if not ok]


def discover_px4_output_topics(
    topic_names_and_types: list[tuple[str, list[str]]],
    expected_fqns: dict[str, str],
) -> TopicDiscoveryResult:
    name_to_types = {name: types for name, types in topic_names_and_types}
    present: dict[str, bool] = {}
    advertised: dict[str, list[str]] = {}
    for key, fqn in expected_fqns.items():
        types = name_to_types.get(fqn, [])
        present[key] = bool(types)
        advertised[key] = list(types)
    return TopicDiscoveryResult(expected=expected_fqns, present=present, advertised_types=advertised)

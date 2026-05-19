"""Multi-vehicle ROS 2 connection configuration (parallel to MAVSDK bridge vehicle keys)."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Any

import yaml


def ros_safe_node_name_suffix(vehicle_id: str) -> str:
    """rclpy node name token from Guardian ``vehicle_id`` (e.g. ``sysid:147`` → ``sysid_147``)."""
    token = re.sub(r"[^a-zA-Z0-9_]", "_", (vehicle_id or "").strip())
    if not token:
        return "vehicle"
    if token[0].isdigit():
        token = f"v_{token}"
    return token


class AutopilotStack(str, Enum):
    PX4 = "px4"
    # TODO(ardupilot): ArduPilot ROS 2 bridge — separate topic graph and message types.
    ARDUPILOT = "ardupilot"


class FleetVehicleClass(str, Enum):
    """Granular class codes aligned with Guardian ``FleetVehicleType``."""

    UAV_COPTER = "uav_copter"
    UAV_FIXED_WING = "uav_fixed_wing"
    UAV_VTOL = "uav_vtol"
    UGV_WHEELED = "ugv_wheeled"
    UGV_TRACKED = "ugv_tracked"
    UGV_LEGGED = "ugv_legged"
    USV = "usv"
    UUV = "uuv"
    UNKNOWN = "unknown"

    @classmethod
    def from_config_value(cls, raw: str | None) -> FleetVehicleClass:
        if raw is None or not str(raw).strip():
            return cls.UNKNOWN
        key = str(raw).strip().lower().replace("-", "_")
        aliases = {
            "uavcopter": cls.UAV_COPTER,
            "uav_c": cls.UAV_COPTER,
            "uav-c": cls.UAV_COPTER,
            "uavfixedwing": cls.UAV_FIXED_WING,
            "uav_f": cls.UAV_FIXED_WING,
            "uav-f": cls.UAV_FIXED_WING,
            "uavvtol": cls.UAV_VTOL,
            "uav_v": cls.UAV_VTOL,
            "uav-v": cls.UAV_VTOL,
            "ugvwheeled": cls.UGV_WHEELED,
            "ugv_w": cls.UGV_WHEELED,
            "ugv-w": cls.UGV_WHEELED,
            "ugvtracked": cls.UGV_TRACKED,
            "ugv_t": cls.UGV_TRACKED,
            "ugv-t": cls.UGV_TRACKED,
            "ugvlegged": cls.UGV_LEGGED,
            "ugv_l": cls.UGV_LEGGED,
            "ugv-l": cls.UGV_LEGGED,
        }
        if key in aliases:
            return aliases[key]
        for member in cls:
            if member.value == key:
                return member
        return cls.UNKNOWN


@dataclass(frozen=True)
class VehicleConnectionConfig:
    """One ROS 2 connection slot — teardown follows ``vehicle_id`` like MAVSDK stream keys."""

    vehicle_id: str
    stack: AutopilotStack = AutopilotStack.PX4
    vehicle_class: FleetVehicleClass = FleetVehicleClass.UNKNOWN
    ros_namespace: str = ""
    autonomy_planner: str = ""
    enabled: bool = True
    brain_id: str = ""
    brain_version: int = 0
    nav2_param_overlay_json: str = ""
    aerostack2_param_overlay_json: str = ""

    def normalized_namespace(self) -> str:
        ns = (self.ros_namespace or "").strip().strip("/")
        return ns

    def topic_fqn(self, relative: str) -> str:
        """Build absolute topic path for PX4 uXRCE-DDS (e.g. ``/px4_0/fmu/out/vehicle_status``)."""
        rel = relative.strip().strip("/")
        ns = self.normalized_namespace()
        if ns:
            return f"/{ns}/{rel}"
        return f"/{rel}"

    def brain_overlay_detail(self) -> dict[str, object]:
        detail: dict[str, object] = {}
        if self.brain_id:
            detail["brain_id"] = self.brain_id
        if self.brain_version > 0:
            detail["brain_version"] = self.brain_version
        if self.nav2_param_overlay_json:
            detail["nav2_param_overlay_present"] = True
        if self.aerostack2_param_overlay_json:
            detail["aerostack2_param_overlay_present"] = True
        return detail

    def to_dict(self) -> dict[str, Any]:
        row: dict[str, Any] = {
            "vehicle_id": self.vehicle_id,
            "stack": self.stack.value,
            "vehicle_class": self.vehicle_class.value,
            "ros_namespace": self.ros_namespace,
            "autonomy_planner": self.autonomy_planner,
            "enabled": self.enabled,
        }
        if self.brain_id:
            row["brain_id"] = self.brain_id
        if self.brain_version > 0:
            row["brain_version"] = self.brain_version
        if self.nav2_param_overlay_json:
            row["nav2_param_overlay_json"] = self.nav2_param_overlay_json
        if self.aerostack2_param_overlay_json:
            row["aerostack2_param_overlay_json"] = self.aerostack2_param_overlay_json
        return row

    @classmethod
    def from_mapping(cls, raw: dict[str, Any]) -> VehicleConnectionConfig:
        vehicle_id = str(raw.get("vehicle_id", "")).strip()
        if not vehicle_id:
            raise ValueError("vehicle_id is required")

        stack_raw = str(raw.get("stack", AutopilotStack.PX4.value)).strip().lower()
        try:
            stack = AutopilotStack(stack_raw)
        except ValueError as exc:
            raise ValueError(f"unsupported stack: {stack_raw}") from exc

        if stack is AutopilotStack.ARDUPILOT:
            # TODO(ardupilot): parse ArduPilot-specific namespace and topic roots.
            raise ValueError("ardupilot stack is not implemented yet")

        vehicle_class = FleetVehicleClass.from_config_value(raw.get("vehicle_class"))
        ros_namespace = str(raw.get("ros_namespace", "") or "")
        autonomy_planner = str(raw.get("autonomy_planner", "") or "")
        enabled = bool(raw.get("enabled", True))
        brain_id = str(raw.get("brain_id", "") or "").strip()
        brain_version = int(raw.get("brain_version", 0) or 0)
        nav2_param_overlay_json = str(raw.get("nav2_param_overlay_json", "") or "")
        aerostack2_param_overlay_json = str(raw.get("aerostack2_param_overlay_json", "") or "")
        return cls(
            vehicle_id=vehicle_id,
            stack=stack,
            vehicle_class=vehicle_class,
            ros_namespace=ros_namespace,
            autonomy_planner=autonomy_planner,
            enabled=enabled,
            brain_id=brain_id,
            brain_version=brain_version,
            nav2_param_overlay_json=nav2_param_overlay_json,
            aerostack2_param_overlay_json=aerostack2_param_overlay_json,
        )


@dataclass
class BridgeConfig:
    vehicles: list[VehicleConnectionConfig] = field(default_factory=list)
    discovery_interval_s: float = 2.0
    stale_topic_s: float = 5.0

    @classmethod
    def from_yaml_file(cls, path: str) -> BridgeConfig:
        with open(path, encoding="utf-8") as handle:
            doc = yaml.safe_load(handle) or {}
        return cls.from_mapping(doc)

    @classmethod
    def from_mapping(cls, doc: dict[str, Any]) -> BridgeConfig:
        vehicles_raw = doc.get("vehicles", [])
        vehicles: list[VehicleConnectionConfig] = []
        if isinstance(vehicles_raw, list):
            for item in vehicles_raw:
                if isinstance(item, dict):
                    vehicles.append(VehicleConnectionConfig.from_mapping(item))
        timing = doc.get("timing", {}) if isinstance(doc.get("timing"), dict) else {}
        discovery = float(timing.get("discovery_interval_s", 2.0))
        stale = float(timing.get("stale_topic_s", 5.0))
        return cls(vehicles=vehicles, discovery_interval_s=discovery, stale_topic_s=stale)

    def enabled_vehicles(self) -> list[VehicleConnectionConfig]:
        return [v for v in self.vehicles if v.enabled]


def load_bridge_config_from_env() -> BridgeConfig | None:
    path = os.environ.get("GUARDIAN_ROS2_BRIDGE_CONFIG", "").strip()
    if not path:
        return None
    return BridgeConfig.from_yaml_file(path)

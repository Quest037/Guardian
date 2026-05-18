"""
Generic PX4 ROS 2 vehicle connection node (uXRCE-DDS).

Subscribes to basic ``fmu/out`` status topics when ``px4_msgs`` is available.
Does not publish commands or offboard setpoints.
"""

from __future__ import annotations

import time
from typing import Any, Callable

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data

from guardian_ros2_vehicle_bridge.command_extension_points import command_stub_for_class
from guardian_ros2_vehicle_bridge.connection_state import Ros2ConnectionState
from guardian_ros2_vehicle_bridge.json_emit import emit_vehicle, log_err
from guardian_ros2_vehicle_bridge.px4_topics import (
    PX4_BASIC_OUTPUT_TOPICS,
    PX4_BASIC_OUTPUT_TYPES,
    TopicDiscoveryResult,
    discover_px4_output_topics,
)
from guardian_ros2_vehicle_bridge.vehicle_config import (
    VehicleConnectionConfig,
    ros_safe_node_name_suffix,
)

try:
    from px4_msgs.msg import (
        BatteryStatus,
        VehicleGlobalPosition,
        VehicleLocalPosition,
        VehicleOdometry,
        VehicleStatus,
    )

    _PX4_MSGS_AVAILABLE = True
except ImportError:
    _PX4_MSGS_AVAILABLE = False


class Px4VehicleConnectionNode(Node):
    """One rclpy node per configured vehicle."""

    def __init__(
        self,
        config: VehicleConnectionConfig,
        *,
        stale_topic_s: float = 5.0,
        on_state_change: Callable[[str, Ros2ConnectionState, dict[str, Any]], None] | None = None,
    ) -> None:
        safe_name = ros_safe_node_name_suffix(config.vehicle_id)
        super().__init__(f"guardian_px4_{safe_name}")
        self._config = config
        self._stale_topic_s = stale_topic_s
        self._on_state_change = on_state_change
        self._state = Ros2ConnectionState.DISCONNECTED
        self._last_discovery: TopicDiscoveryResult | None = None
        self._last_msg_monotonic: dict[str, float] = {}
        self._subscriptions: list[Any] = []

        self._command_stub = command_stub_for_class(config)
        self._expected_fqns = {
            key: config.topic_fqn(rel) for key, rel in PX4_BASIC_OUTPUT_TOPICS.items()
        }

        self._set_state(Ros2ConnectionState.CONNECTING)
        self._create_subscriptions_if_possible()
        self.create_timer(2.0, self._on_discovery_timer)

    @property
    def vehicle_id(self) -> str:
        return self._config.vehicle_id

    @property
    def connection_state(self) -> Ros2ConnectionState:
        return self._state

    def matches_config(self, other: VehicleConnectionConfig) -> bool:
        return (
            self._config.vehicle_id == other.vehicle_id
            and self._config.stack == other.stack
            and self._config.vehicle_class == other.vehicle_class
            and self._config.normalized_namespace() == other.normalized_namespace()
            and self._config.enabled == other.enabled
        )

    def snapshot_health(self) -> dict[str, Any]:
        discovery = self._last_discovery
        return {
            "vehicle_id": self._config.vehicle_id,
            "stack": self._config.stack.value,
            "vehicle_class": self._config.vehicle_class.value,
            "ros_namespace": self._config.ros_namespace,
            "state": self._state.to_json(),
            "px4_msgs_available": _PX4_MSGS_AVAILABLE,
            "expected_topics": dict(self._expected_fqns),
            "topics_present": dict(discovery.present) if discovery else {},
            "topics_missing": discovery.missing_keys() if discovery else list(self._expected_fqns.keys()),
            "last_message_age_s": {
                k: round(max(0.0, time.monotonic() - t), 2)
                for k, t in self._last_msg_monotonic.items()
            },
            "future_command_roots": self._command_stub.topic_roots(),
        }

    def _set_state(self, new_state: Ros2ConnectionState) -> None:
        if new_state == self._state:
            return
        self._state = new_state
        payload = {"type": "ros2_connection_state", "state": new_state.to_json()}
        emit_vehicle(self.vehicle_id, payload)
        if self._on_state_change:
            self._on_state_change(self.vehicle_id, new_state, self.snapshot_health())

    def _mark_topic_received(self, key: str) -> None:
        self._last_msg_monotonic[key] = time.monotonic()

    def _create_subscriptions_if_possible(self) -> None:
        if not _PX4_MSGS_AVAILABLE:
            log_err(
                f"[{self.vehicle_id}] px4_msgs not installed — topic discovery only; "
                "install ros-$ROS_DISTRO-px4-msgs or build px4_msgs from PX4-Autopilot."
            )
            return

        handlers: list[tuple[str, type, Callable]] = [
            ("vehicle_status", VehicleStatus, self._on_vehicle_status),
            ("vehicle_local_position", VehicleLocalPosition, self._on_vehicle_local_position),
            ("vehicle_global_position", VehicleGlobalPosition, self._on_vehicle_global_position),
            ("battery_status", BatteryStatus, self._on_battery_status),
            ("vehicle_odometry", VehicleOdometry, self._on_vehicle_odometry),
        ]
        for key, msg_type, callback in handlers:
            fqn = self._expected_fqns[key]
            try:
                sub = self.create_subscription(
                    msg_type,
                    fqn,
                    callback,
                    qos_profile_sensor_data,
                )
                self._subscriptions.append(sub)
            except Exception as exc:
                log_err(f"[{self.vehicle_id}] subscription failed for {fqn}: {exc}")

    def _on_discovery_timer(self) -> None:
        names_types = self.get_topic_names_and_types()
        discovery = discover_px4_output_topics(names_types, self._expected_fqns)
        self._last_discovery = discovery

        emit_vehicle(
            self.vehicle_id,
            {
                "type": "ros2_topic_discovery",
                "topics_present": discovery.present,
                "topics_missing": discovery.missing_keys(),
                "advertised_types": discovery.advertised_types,
            },
        )

        now = time.monotonic()
        stale_keys = [
            k
            for k in self._expected_fqns
            if k not in self._last_msg_monotonic
            or (now - self._last_msg_monotonic[k]) > self._stale_topic_s
        ]

        if not discovery.any_present:
            self._set_state(Ros2ConnectionState.CONNECTING)
            return

        if not _PX4_MSGS_AVAILABLE:
            self._set_state(
                Ros2ConnectionState.DEGRADED if discovery.any_present else Ros2ConnectionState.CONNECTING
            )
            return

        if discovery.all_present and not stale_keys:
            self._set_state(Ros2ConnectionState.CONNECTED)
        elif discovery.any_present:
            self._set_state(Ros2ConnectionState.DEGRADED)
        else:
            self._set_state(Ros2ConnectionState.ERROR)

    def _on_vehicle_status(self, msg: VehicleStatus) -> None:
        self._mark_topic_received("vehicle_status")
        emit_vehicle(
            self.vehicle_id,
            {
                "type": "ros2_vehicle_status",
                "arming_state": int(msg.arming_state),
                "nav_state": int(msg.nav_state),
            },
        )

    def _on_vehicle_local_position(self, msg: VehicleLocalPosition) -> None:
        self._mark_topic_received("vehicle_local_position")
        emit_vehicle(
            self.vehicle_id,
            {
                "type": "ros2_vehicle_local_position",
                "x": float(msg.x),
                "y": float(msg.y),
                "z": float(msg.z),
            },
        )

    def _on_vehicle_global_position(self, msg: VehicleGlobalPosition) -> None:
        self._mark_topic_received("vehicle_global_position")
        emit_vehicle(
            self.vehicle_id,
            {
                "type": "ros2_vehicle_global_position",
                "lat": float(msg.lat),
                "lon": float(msg.lon),
                "alt": float(msg.alt),
            },
        )

    def _on_battery_status(self, msg: BatteryStatus) -> None:
        self._mark_topic_received("battery_status")
        emit_vehicle(
            self.vehicle_id,
            {
                "type": "ros2_battery_status",
                "voltage_v": float(msg.voltage_v),
                "remaining": float(msg.remaining),
            },
        )

    def _on_vehicle_odometry(self, msg: VehicleOdometry) -> None:
        self._mark_topic_received("vehicle_odometry")
        emit_vehicle(
            self.vehicle_id,
            {
                "type": "ros2_vehicle_odometry",
                "position": [float(msg.position[0]), float(msg.position[1]), float(msg.position[2])],
            },
        )

    def destroy_node(self) -> bool:
        self._set_state(Ros2ConnectionState.DISCONNECTED)
        return super().destroy_node()
